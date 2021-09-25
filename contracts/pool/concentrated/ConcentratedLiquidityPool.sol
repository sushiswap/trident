// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../../interfaces/IBentoBoxMinimal.sol";
import "../../interfaces/IMasterDeployer.sol";
import "../../interfaces/IPool.sol";
import "../../interfaces/IPositionManager.sol";
import "../../interfaces/ITridentCallee.sol";
import "../../interfaces/ITridentRouter.sol";
import "../../libraries/concentratedPool/FullMath.sol";
import "../../libraries/concentratedPool/TickMath.sol";
import "../../libraries/concentratedPool/UnsafeMath.sol";
import "../../libraries/concentratedPool/DyDxMath.sol";
import "../../libraries/concentratedPool/SwapLib.sol";
import "../../libraries/concentratedPool/Ticks.sol";
import "hardhat/console.sol";

/// @notice Trident exchange pool template with concentrated liquidity and constant product formula for swapping between an ERC-20 token pair.
/// @dev The reserves are stored as bento shares.
//      The curve is applied to shares as well. This pool does not care about the underlying amounts.
contract ConcentratedLiquidityPool is IPool {
    using Ticks for mapping(int24 => Ticks.Tick);

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Collect(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserveShares0, uint256 reserveShares1);

    address public immutable barFeeTo;
    IBentoBoxMinimal public immutable bento;
    IMasterDeployer public immutable masterDeployer;
    address public immutable poolManager;
    address public immutable token0;
    address public immutable token1;
    
    uint32 public lastObservation; 
    uint128 public liquidity;
    uint160 public secondsPerLiquidity; /// @dev Multiplied by 2^128. 
    
    uint256 public feeGrowthGlobal0; /// @dev All fee growth counters are multiplied by 2^128.
    uint256 public feeGrowthGlobal1;
    
    uint256 public barFee;
    uint128 public token0ProtocolFee; 
    uint128 public token1ProtocolFee;
    
    uint128 public reserve0; /// @dev Bento share balance tracker.
    uint128 public reserve1; 

    uint160 public price; /// @dev Sqrt of price aka. √(y/x), multiplied by 2^96. 
    int24 public nearestTick; /// @dev Tick that is just below the current price. 
    
    /// @dev References for tickSpacing:
    // - univ3 1% -> 200 tickSpacing
    // - univ3 0.3% pool -> 60 tickSpacing -> 0.6% between ticks
    // - univ3 0.05% pool -> 10 tickSpacing -> 0.1% between ticks
    // - 100 tickSpacing -> 1% between ticks => 2% between ticks on starting position (*stable pairs are different)
    uint24 public immutable tickSpacing;
    
    uint24 internal constant MAX_FEE = 10000; /// @dev 100%. 
    uint24 public immutable swapFee; /// @dev 1000 corresponds to 0.1% fee.

    bytes32 public constant override poolIdentifier = "Trident:ConcentratedLiquidity";
    
    uint256 internal unlocked;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }
    
    mapping(int24 => Ticks.Tick) public ticks;
    mapping(address => mapping(int24 => mapping(int24 => Position))) public positions;

    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0Last;
        uint256 feeGrowthInside1Last;
        uint160 secondsPerLiquidityLast; /// <- might want to store this in the manager contract only
    }

    struct SwapCache {
        uint256 feeAmount;
        uint256 totalFeeAmount;
        uint256 protocolFee;
        uint256 feeGrowthGlobal;
        uint256 currentPrice;
        uint256 currentLiquidity;
        uint256 input;
        int24 nextTickToCross;
    }

    struct MintParams {
        int24 lowerOld; 
        int24 lower; 
        int24 upperOld; 
        int24 upper; 
        address positionOwner;
        address recipient;
        bool amount0native; 
        bool amount1native; 
        uint256 amount0Desired;
        uint256 amount1Desired;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(
        bytes memory _deployData,
        IMasterDeployer _masterDeployer,
        address _poolManager
    ) {
        (address _token0, address _token1, uint24 _swapFee, uint160 _price, uint24 _tickSpacing) = abi.decode(
            _deployData, 
            (address, address, uint24, uint160, uint24)
        );

        require(_token0 != address(0), "ZERO_ADDRESS");
        require(_token0 != _token1, "IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "INVALID_SWAP_FEE");

        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        price = _price;
        tickSpacing = _tickSpacing;
        ticks[TickMath.MIN_TICK] = Ticks.Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), 0, 0, 0);
        ticks[TickMath.MAX_TICK] = Ticks.Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), 0, 0, 0);
        nearestTick = TickMath.MIN_TICK;
        bento = IBentoBoxMinimal(_masterDeployer.bento());
        barFeeTo = _masterDeployer.barFeeTo();
        barFee = _masterDeployer.barFee();
        masterDeployer = _masterDeployer;
        poolManager = _poolManager;
        unlocked = 1;
    }
    
    /// @dev Mints LP tokens - should be called via the router after transferring `bento` tokens.
    // The router must ensure that sufficient LP tokens are minted by using the return value.
    function mint(bytes calldata data) external override lock returns (uint256 _liquidity) {
        MintParams memory mintParams = abi.decode(data, (MintParams));

        uint256 priceLower = uint256(TickMath.getSqrtRatioAtTick(mintParams.lower));
        uint256 priceUpper = uint256(TickMath.getSqrtRatioAtTick(mintParams.upper));
        uint256 currentPrice = uint256(price);

        _liquidity = DyDxMath.getLiquidityForAmounts(
            priceLower,
            priceUpper,
            currentPrice,
            mintParams.amount1Desired,
            mintParams.amount0Desired
        );

        /// @dev This is safe because overflow is checked in position minter contract.
        unchecked {
            if (priceLower < currentPrice && currentPrice < priceUpper) liquidity += uint128(_liquidity);
        }

        /// @dev Fees should have been collected before position updates.
        _updatePosition(mintParams.positionOwner, mintParams.lower, mintParams.upper, int128(uint128(_liquidity)));

        (nearestTick) = Ticks.insert(
            ticks,
            nearestTick,
            tickSpacing,
            feeGrowthGlobal0,
            feeGrowthGlobal1,
            secondsPerLiquidity,
            mintParams.lowerOld,
            mintParams.lower,
            mintParams.upperOld,
            mintParams.upper,
            uint128(_liquidity),
            uint160(currentPrice)
        );

        {
            (uint128 amount0Actual, uint128 amount1Actual) = _getAmountsForLiquidity(priceLower, priceUpper, currentPrice, _liquidity);

            ITridentRouter.TokenInput[] memory callbackData = new ITridentRouter.TokenInput[](2);
            callbackData[0] = ITridentRouter.TokenInput(token0, mintParams.amount0native, amount0Actual);
            callbackData[1] = ITridentRouter.TokenInput(token1, mintParams.amount1native, amount1Actual);

            ITridentCallee(msg.sender).tridentMintCallback(abi.encode(callbackData));

            /// @dev This is safe because overflow is checked in {getAmountsForLiquidity}.
            unchecked {
                if (amount0Actual != 0) {
                    require(amount0Actual + reserve0 <= _balance(token0), "TOKEN0_MISSING");
                    reserve0 += amount0Actual;
                }

                if (amount1Actual != 0) {
                    require(amount1Actual + reserve1 <= _balance(token1), "TOKEN1_MISSING");
                    reserve1 += amount1Actual;
                }
            }

            (uint256 feeGrowth0, uint256 feeGrowth1) = rangeFeeGrowth(mintParams.lower, mintParams.upper);

            IPositionManager(poolManager).positionMintCallback(
                mintParams.recipient,
                mintParams.lower,
                mintParams.upper,
                uint128(_liquidity),
                feeGrowth0,
                feeGrowth1
            );

            emit Mint(msg.sender, amount0Actual, amount1Actual, mintParams.recipient);
        }

        return _liquidity;
    }
    
    /// @dev Burns LP tokens sent to this contract. The router must ensure that the user gets sufficient output tokens.
    function burn(bytes calldata data) external override lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (int24 lower, int24 upper, uint128 amount, address recipient, bool unwrapBento) = abi.decode(
            data,
            (int24, int24, uint128, address, bool)
        );

        uint160 priceLower = TickMath.getSqrtRatioAtTick(lower);
        uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);
        uint160 currentPrice = price;
        /// @dev This is safe because user cannot have overflow amount of LP to burn.
        unchecked {
            if (priceLower < currentPrice && currentPrice < priceUpper) liquidity -= amount;
        }

        (uint256 amount0, uint256 amount1) = _getAmountsForLiquidity(
            uint256(priceLower),
            uint256(priceUpper),
            uint256(currentPrice),
            uint256(amount)
        );

        (uint256 amount0fees, uint256 amount1fees) = _updatePosition(msg.sender, lower, upper, -int128(amount));
        /// @dev This is safe because overflow is checked in {updatePosition}.
        unchecked {
            amount0 += amount0fees;
            amount1 += amount1fees;
        }

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: token0, amount: amount0});
        withdrawnAmounts[1] = TokenAmount({token: token1, amount: amount1});

        _transfer(token0, amount0, recipient, unwrapBento);
        _transfer(token1, amount1, recipient, unwrapBento);

        (nearestTick) = Ticks.remove(ticks, nearestTick, lower, upper, amount);
        emit Burn(msg.sender, amount0, amount1, recipient);
    }
    
    /// @dev Reserved for IPool.
    function burnSingle(bytes calldata) public pure override returns (uint256 amountOut) {
        return amountOut;
    }
    
    /// @dev Collects LP token fees for user and updates position.
    function collect(bytes calldata data) external lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (int24 lower, int24 upper, address recipient, bool unwrapBento) = abi.decode(data, (int24, int24, address, bool));

        (uint256 amount0fees, uint256 amount1fees) = _updatePosition(msg.sender, lower, upper, 0);

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: token0, amount: amount0fees});
        withdrawnAmounts[1] = TokenAmount({token: token1, amount: amount1fees});

        _transfer(token0, amount0fees, recipient, unwrapBento);
        _transfer(token1, amount1fees, recipient, unwrapBento);

        emit Collect(msg.sender, amount0fees, amount1fees);
    }
    
    /// @dev Swaps one token for another. The router must prefund this contract and ensure there isn't too much slippage
    // - price is √(y/x)
    // - x is token0
    // - zero for one -> price will move down.
    function swap(bytes memory data) public override lock returns (uint256 amountOut) {
        (bool zeroForOne, uint256 inAmount, address recipient, bool unwrapBento) = abi.decode(data, (bool, uint256, address, bool));

        SwapCache memory cache = SwapCache({
            feeAmount: 0,
            totalFeeAmount: 0,
            protocolFee: 0,
            feeGrowthGlobal: zeroForOne ? feeGrowthGlobal1 : feeGrowthGlobal0,
            currentPrice: uint256(price),
            currentLiquidity: uint256(liquidity),
            input: inAmount,
            nextTickToCross: zeroForOne ? nearestTick : ticks[nearestTick].nextTick
        });

        {
            uint256 timestamp = block.timestamp;
            uint256 diff = timestamp - uint256(lastObservation); /// @dev Underflow in 2106.
            if (diff > 0 && liquidity > 0) {
                lastObservation = uint32(timestamp);
                secondsPerLiquidity += uint160((diff << 128) / liquidity);
            }
        }

        while (cache.input != 0) {
            uint256 nextTickPrice = uint256(TickMath.getSqrtRatioAtTick(cache.nextTickToCross));
            uint256 output;
            bool cross;
            if (zeroForOne) {
                /// @dev x for y
                // - price is going down
                // - max swap input within current tick range: Δx = Δ(1/√𝑃) · L.
                uint256 maxDx = DyDxMath.getDx(cache.currentLiquidity, nextTickPrice, cache.currentPrice, false);
                
                if (cache.input <= maxDx) {
                    /// @dev We can swap only within the current range.
                    uint256 liquidityPadded = cache.currentLiquidity << 96;
                    /// @dev Calculate new price after swap: √𝑃[new] =  L · √𝑃 / (L + Δx · √𝑃)
                    // ^ This is derrived from Δ(1/√𝑃)=Δx/L
                    // (where Δ(1/√𝑃) is (1/√𝑃[old] - 1/√𝑃[new]) and we solve for √𝑃[new])
                    // if an overflow happens we can use: √𝑃[new] = L / (L / √𝑃 + Δx)
                    // ^ same as the above formula, but the fraction is divided by √𝑃.
                    uint256 newPrice = uint256(
                        FullMath.mulDivRoundingUp(liquidityPadded, cache.currentPrice, liquidityPadded + cache.currentPrice * cache.input)
                    );

                    if (!(nextTickPrice <= newPrice && newPrice < cache.currentPrice)) {
                        /// @dev Overflow -> use a modified version of the formula.
                        newPrice = uint160(UnsafeMath.divRoundingUp(liquidityPadded, liquidityPadded / cache.currentPrice + cache.input));
                    }
                    /// @dev Calculate output of swap
                    // - Δy = Δ√P · L.
                    output = DyDxMath.getDy(cache.currentLiquidity, newPrice, cache.currentPrice, false);
                    cache.currentPrice = newPrice;
                    cache.input = 0;
                } else {
                    /// @dev Swap & cross the tick.
                    output = DyDxMath.getDy(cache.currentLiquidity, nextTickPrice, cache.currentPrice, false);
                    cache.currentPrice = nextTickPrice;
                    cross = true;
                    cache.input -= maxDx;
                }
            } else {
                /// @dev Price is going up
                // - max swap within current tick range: Δy = Δ√P · L.
                uint256 maxDy = DyDxMath.getDy(cache.currentLiquidity, cache.currentPrice, nextTickPrice, false);
                if (cache.input <= maxDy) {
                    /// @dev We can swap only within the current range
                    // - calculate new price after swap ( ΔP = Δy/L ).
                    uint256 newPrice = cache.currentPrice +
                        FullMath.mulDiv(cache.input, 0x1000000000000000000000000, cache.currentLiquidity);
                    /// @dev Calculate output of swap
                    // - Δx = Δ(1/√P) · L.
                    output = DyDxMath.getDx(cache.currentLiquidity, cache.currentPrice, newPrice, false);
                    cache.currentPrice = newPrice;
                    cache.input = 0;
                } else {
                    /// @dev Swap & cross the tick.
                    output = DyDxMath.getDx(cache.currentLiquidity, cache.currentPrice, nextTickPrice, false);
                    cache.currentPrice = nextTickPrice;
                    cross = true;
                    cache.input -= maxDy;
                }
            }

            (cache.totalFeeAmount, amountOut, cache.protocolFee, cache.feeGrowthGlobal) = SwapLib.handleFees(
                output,
                swapFee,
                barFee,
                cache.currentLiquidity,
                cache.totalFeeAmount,
                amountOut,
                cache.protocolFee,
                cache.feeGrowthGlobal
            );

            if (cross) {
                (cache.currentLiquidity, cache.nextTickToCross) = Ticks.cross(
                    ticks,
                    cache.nextTickToCross,
                    secondsPerLiquidity,
                    cache.currentLiquidity,
                    cache.feeGrowthGlobal,
                    zeroForOne
                );
            }
        }

        price = uint160(cache.currentPrice);

        int24 newNearestTick = zeroForOne ? cache.nextTickToCross : ticks[cache.nextTickToCross].previousTick;

        if (nearestTick != newNearestTick) {
            nearestTick = newNearestTick;
            liquidity = uint128(cache.currentLiquidity);
        }

        _updateReserves(zeroForOne, uint128(inAmount), amountOut, cache.totalFeeAmount);

        _updateFees(zeroForOne, cache.feeGrowthGlobal, uint128(cache.protocolFee));

        if (zeroForOne) {
            _transfer(token1, amountOut, recipient, unwrapBento);
            emit Swap(recipient, token0, token1, inAmount, amountOut);
        } else {
            _transfer(token0, amountOut, recipient, unwrapBento);
            emit Swap(recipient, token1, token0, inAmount, amountOut);
        }
    }
    
    /// @dev Reserved for IPool.
    function flashSwap(bytes calldata) public pure override returns (uint256 finalAmountOut) {
        return finalAmountOut;
    }
    
    /// @dev Updates `barFee` for Trident protocol.
    function updateBarFee() public {
        barFee = IMasterDeployer(masterDeployer).barFee();
    }
    
    /// @dev Collects fees for Trident protocol.
    function collectProtocolFee() public lock {
        _transfer(token0, token0ProtocolFee - 1, barFeeTo, false);
        _transfer(token1, token1ProtocolFee - 1, barFeeTo, false);
        token0ProtocolFee = 1;
        token1ProtocolFee = 1;
    }
    
    function _balance(address token) internal view returns (uint256 balance) {
        balance = bento.balanceOf(token, address(this));
    }
    
    function _getAmountsForLiquidity(
        uint256 priceLower,
        uint256 priceUpper,
        uint256 currentPrice,
        uint256 liquidityAmount
    ) internal pure returns (uint128 token0amount, uint128 token1amount) {
        if (priceUpper <= currentPrice) {
            /// @dev Only supply token1 (token1 is Y).
            token1amount = uint128(DyDxMath.getDy(liquidityAmount, priceLower, priceUpper, true));
        } else if (currentPrice <= priceLower) {
            /// @dev Only supply token0 (token0 is X).
            token0amount = uint128(DyDxMath.getDx(liquidityAmount, priceLower, priceUpper, true));
        } else {
            /// @dev Supply both tokens.
            token0amount = uint128(DyDxMath.getDx(liquidityAmount, currentPrice, priceUpper, true));
            token1amount = uint128(DyDxMath.getDy(liquidityAmount, priceLower, currentPrice, true));
        }
    }

    function _updateReserves(
        bool zeroForOne,
        uint128 inAmount,
        uint256 amountOut,
        uint256 totalFeeAmount
    ) internal {
        if (zeroForOne) {
            uint256 balance0 = _balance(token0);
            uint128 newBalance = reserve0 + inAmount;
            require(uint256(newBalance) <= balance0, "TOKEN0_MISSING");
            reserve0 = newBalance;
            reserve1 -= (uint128(amountOut) + uint128(totalFeeAmount));
        } else {
            uint256 balance1 = _balance(token1);
            uint128 newBalance = reserve1 + inAmount;
            require(uint256(newBalance) <= balance1, "TOKEN1_MISSING");
            reserve1 = newBalance;
            reserve0 -= (uint128(amountOut) + uint128(totalFeeAmount));
        }
    }

    function _updateFees(
        bool zeroForOne,
        uint256 feeGrowthGlobal,
        uint128 protocolFee
    ) internal {
        if (zeroForOne) {
            feeGrowthGlobal1 += feeGrowthGlobal;
            token1ProtocolFee += protocolFee;
        } else {
            feeGrowthGlobal0 += feeGrowthGlobal;
            token0ProtocolFee += protocolFee;
        }
    }

    function _updatePosition(
        address owner,
        int24 lower,
        int24 upper,
        int128 amount
    ) internal returns (uint256 amount0fees, uint256 amount1fees) {
        Position storage position = positions[owner][lower][upper];

        (uint256 growth0current, uint256 growth1current) = rangeFeeGrowth(lower, upper);

        amount0fees = FullMath.mulDiv(
            growth0current - position.feeGrowthInside0Last,
            position.liquidity,
            0x100000000000000000000000000000000
        );

        amount1fees = FullMath.mulDiv(
            growth1current - position.feeGrowthInside1Last,
            position.liquidity,
            0x100000000000000000000000000000000
        );

        if (amount < 0) position.liquidity -= uint128(amount);
        if (amount > 0) position.liquidity += uint128(amount);

        position.feeGrowthInside0Last = growth0current;
        position.feeGrowthInside1Last = growth1current;
    }
    
    function _transfer(
        address token,
        uint256 shares,
        address to,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token, address(this), to, 0, shares);
        } else {
            bento.transfer(token, address(this), to, shares);
        }
    }

    /// @dev Generic formula for fee growth inside a range: (globalGrowth - growthBelow - growthAbove)
    // - available counters: global, outside u, outside v.

    //                  u         ▼         v
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - feeGrowthOutside(u) - feeGrowthOutside(v))

    //             ▼    u                   v
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - (global - feeGrowthOutside(u)) - feeGrowthOutside(v))

    //                  u                   v    ▼
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - feeGrowthOutside(u) - (global - feeGrowthOutside(v)))

    /// @notice Calculates the fee growth inside a range (per unit of liquidity).
    /// @dev Multiply `rangeFeeGrowth` delta by the provided liquidity to get accrued fees for some period.
    function rangeFeeGrowth(int24 lowerTick, int24 upperTick) public view returns (uint256 feeGrowthInside0, uint256 feeGrowthInside1) {
        int24 currentTick = nearestTick;

        Ticks.Tick storage lower = ticks[lowerTick];
        Ticks.Tick storage upper = ticks[upperTick];

        /// @dev Calculate fee growth below & above.
        uint256 _feeGrowthGlobal0 = feeGrowthGlobal0;
        uint256 _feeGrowthGlobal1 = feeGrowthGlobal1;
        uint256 feeGrowthBelow0;
        uint256 feeGrowthBelow1;
        uint256 feeGrowthAbove0;
        uint256 feeGrowthAbove1;

        if (lowerTick <= currentTick) {
            feeGrowthBelow0 = lower.feeGrowthOutside0;
            feeGrowthBelow1 = lower.feeGrowthOutside1;
        } else {
            feeGrowthBelow0 = _feeGrowthGlobal0 - lower.feeGrowthOutside0;
            feeGrowthBelow1 = _feeGrowthGlobal1 - lower.feeGrowthOutside1;
        }

        if (currentTick < upperTick) {
            feeGrowthAbove0 = upper.feeGrowthOutside0;
            feeGrowthAbove1 = upper.feeGrowthOutside1;
        } else {
            feeGrowthAbove0 = _feeGrowthGlobal0 - upper.feeGrowthOutside0;
            feeGrowthAbove1 = _feeGrowthGlobal1 - upper.feeGrowthOutside1;
        }

        feeGrowthInside0 = _feeGrowthGlobal0 - feeGrowthBelow0 - feeGrowthAbove0;
        feeGrowthInside1 = _feeGrowthGlobal1 - feeGrowthBelow1 - feeGrowthAbove1;
    }

    function rangeSecondsInside(int24 lowerTick, int24 upperTick) public view returns (uint256 secondsInside) {
        int24 currentTick = nearestTick;

        Ticks.Tick storage lower = ticks[lowerTick];
        Ticks.Tick storage upper = ticks[upperTick];

        uint256 secondsGlobal = secondsPerLiquidity;
        uint256 secondsBelow;
        uint256 secondsAbove;

        if (lowerTick <= currentTick) {
            secondsBelow = lower.secondsPerLiquidityOutside;
        } else {
            secondsBelow = secondsGlobal - lower.secondsPerLiquidityOutside;
        }

        if (currentTick < upperTick) {
            secondsAbove = upper.secondsPerLiquidityOutside;
        } else {
            secondsAbove = secondsGlobal - upper.secondsPerLiquidityOutside;
        }

        secondsInside = secondsGlobal - secondsBelow - secondsAbove;
    }
    
    function getAssets() public view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }
    
    /// @dev Reserved for IPool.
    function getAmountOut(bytes calldata) public pure override returns (uint256 finalAmountOut) {
        return finalAmountOut;
    }
    
    function getReserves()
        public
        view
        returns (
            uint128 _reserve0,
            uint128 _reserve1,
            uint32 _lastObservation
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _lastObservation = lastObservation;
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IBentoBoxMinimal.sol";
import "../../interfaces/IMasterDeployer.sol";
import "../../interfaces/IPool.sol";
import "../../interfaces/concentratedPool/IPositionManager.sol";
import "../../interfaces/ITridentCallee.sol";
import "../../interfaces/ITridentRouter.sol";
import "../../libraries/concentratedPool/FullMath.sol";
import "../../libraries/concentratedPool/TickMath.sol";
import "../../libraries/concentratedPool/UnsafeMath.sol";
import "../../libraries/concentratedPool/DyDxMath.sol";
import "../../libraries/concentratedPool/SwapLib.sol";
import "../../libraries/concentratedPool/Ticks.sol";
import "hardhat/console.sol";

/// @notice Trident exchange pool template implementing concentrated liquidity for swapping between an ERC-20 token pair.
/// @dev Amounts are considered to be in Bentobox shared
contract ConcentratedLiquidityPool is IPool {
    using Ticks for mapping(int24 => Ticks.Tick);

    event Mint(address indexed owner, uint256 amount0, uint256 amount1);
    event Burn(address indexed owner, uint256 amount0, uint256 amount1);
    event Collect(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserveShares0, uint256 reserveShares1);

    bytes32 public constant override poolIdentifier = "Trident:ConcentratedLiquidity";

    uint24 internal constant MAX_FEE = 100000; /// @dev Maximum `swapFee` is 10%.
    /// @dev References for tickSpacing:
    /// 100 tickSpacing -> 2% between ticks.
    uint24 internal immutable tickSpacing;
    uint24 internal immutable swapFee; /// @dev 1000 corresponds to 0.1% fee. Fee is measured in pips.
    uint128 internal immutable MAX_TICK_LIQUIDITY;

    address internal immutable barFeeTo;
    IBentoBoxMinimal internal immutable bento;
    IMasterDeployer internal immutable masterDeployer;

    address internal immutable token0;
    address internal immutable token1;

    uint128 public liquidity;

    uint160 internal secondsGrowthGlobal; /// @dev Multiplied by 2^128.
    uint32 internal lastObservation;

    uint256 public feeGrowthGlobal0; /// @dev All fee growth counters are multiplied by 2^128.
    uint256 public feeGrowthGlobal1;

    uint256 public barFee;

    uint128 internal token0ProtocolFee;
    uint128 internal token1ProtocolFee;

    uint128 internal reserve0; /// @dev `bento` share balance tracker.
    uint128 internal reserve1;

    uint160 internal price; /// @dev Sqrt of price aka. √(y/x), multiplied by 2^96.
    int24 internal nearestTick; /// @dev Tick that is just below the current price.

    uint256 internal unlocked;

    mapping(int24 => Ticks.Tick) public ticks;
    mapping(address => mapping(int24 => mapping(int24 => Position))) public positions;

    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0Last;
        uint256 feeGrowthInside1Last;
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
        uint256 amount0Desired;
        uint256 amount1Desired;
        bool token0native;
        bool token1native;
        address positionOwner; // To mint an NFT the positionOwner should be set to the positionManager contract.
        address positionRecipient;
        uint256 positionId;
    }

    /// @dev Error list to optimize around pool requirements.
    error Locked();
    error ZeroAddress();
    error InvalidToken();
    error InvalidSwapFee();
    error LiquidityOverflow();
    error Token0Missing();
    error Token1Missing();
    error InvalidTick();
    error LowerEven();
    error UpperOdd();
    error MaxTickLiquidity();
    error Overflow();

    modifier lock() {
        if (unlocked == 2) revert Locked();
        unlocked = 2;
        _;
        unlocked = 1;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, IMasterDeployer _masterDeployer) {
        (address _token0, address _token1, uint24 _swapFee, uint160 _price, uint24 _tickSpacing) = abi.decode(
            _deployData,
            (address, address, uint24, uint160, uint24)
        );

        if (_token0 == address(0)) revert ZeroAddress();
        if (_token0 == address(this)) revert InvalidToken();
        if (_token1 == address(this)) revert InvalidToken();
        if (_swapFee > MAX_FEE) revert InvalidSwapFee();

        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        price = _price;
        tickSpacing = _tickSpacing;
        // Prevents global liquidity overflow in the case all ticks are initialised.
        MAX_TICK_LIQUIDITY = Ticks.getMaxLiquidity(_tickSpacing);
        ticks[TickMath.MIN_TICK] = Ticks.Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), 0, 0, 0);
        ticks[TickMath.MAX_TICK] = Ticks.Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), 0, 0, 0);
        nearestTick = TickMath.MIN_TICK;
        bento = IBentoBoxMinimal(_masterDeployer.bento());
        barFeeTo = _masterDeployer.barFeeTo();
        barFee = _masterDeployer.barFee();
        masterDeployer = _masterDeployer;
        unlocked = 1;
    }

    /// @dev Mints LP tokens - should be called via the router after transferring `bento` tokens.
    /// The router must ensure that sufficient liquidity has been minted.
    function mint(bytes calldata data) public override lock returns (uint256 _liquidity) {
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

        unchecked {
            (uint256 amount0fees, uint256 amount1fees, ) = _updatePosition(
                mintParams.positionOwner,
                mintParams.lower,
                mintParams.upper,
                int128(uint128(_liquidity))
            );
            if (amount0fees > 0) {
                _transfer(token0, amount0fees, mintParams.positionOwner, false);
                reserve0 -= uint128(amount0fees);
            }
            if (amount1fees > 0) {
                _transfer(token1, amount1fees, mintParams.positionOwner, false);
                reserve1 -= uint128(amount1fees);
            }
        }

        unchecked {
            if (priceLower < currentPrice && currentPrice < priceUpper) liquidity += uint128(_liquidity);
        }

        _ensureTickSpacing(mintParams.lower, mintParams.upper);

        nearestTick = Ticks.insert(
            ticks,
            feeGrowthGlobal0,
            feeGrowthGlobal1,
            secondsGrowthGlobal,
            mintParams.lowerOld,
            mintParams.lower,
            mintParams.upperOld,
            mintParams.upper,
            uint128(_liquidity),
            nearestTick,
            uint160(currentPrice)
        );

        (uint128 amount0Actual, uint128 amount1Actual) = DyDxMath.getAmountsForLiquidity(
            priceLower,
            priceUpper,
            currentPrice,
            _liquidity,
            true
        );

        {
            ITridentRouter.TokenInput[] memory callbackData = new ITridentRouter.TokenInput[](2);
            callbackData[0] = ITridentRouter.TokenInput(token0, mintParams.token0native, amount0Actual);
            callbackData[1] = ITridentRouter.TokenInput(token1, mintParams.token1native, amount1Actual);
            ITridentCallee(msg.sender).tridentMintCallback(abi.encode(callbackData));
        }

        unchecked {
            if (amount0Actual != 0) {
                if (amount0Actual + reserve0 > _balance(token0)) revert Token0Missing();
                reserve0 += amount0Actual;
            }

            if (amount1Actual != 0) {
                if (amount1Actual + reserve1 > _balance(token1)) revert Token1Missing();
                reserve1 += amount1Actual;
            }
        }

        (uint256 feeGrowth0, uint256 feeGrowth1) = rangeFeeGrowth(mintParams.lower, mintParams.upper);

        if (mintParams.positionRecipient != address(0)) {
            IPositionManager(mintParams.positionOwner).positionMintCallback(
                mintParams.positionRecipient,
                mintParams.lower,
                mintParams.upper,
                uint128(_liquidity),
                feeGrowth0,
                feeGrowth1,
                mintParams.positionId
            );
        }

        emit Mint(mintParams.positionOwner, amount0Actual, amount1Actual);
    }

    /// @notice Burn function that cannpt conform to the IPool interface due to having three return values.
    /// @dev Burns LP tokens sent to this contract.
    function decreaseLiquidity(
        int24 lower,
        int24 upper,
        uint128 amount,
        address recipient,
        bool unwrapBento
    )
        public
        returns (
            IPool.TokenAmount[] memory withdrawnAmounts,
            IPool.TokenAmount[] memory feesWithdrawn,
            uint256 oldLiquidity
        )
    {
        uint256 amount0;
        uint256 amount1;

        {
            uint160 priceLower = TickMath.getSqrtRatioAtTick(lower);
            uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);
            uint160 currentPrice = price;

            unchecked {
                if (priceLower < currentPrice && currentPrice < priceUpper) liquidity -= amount;
            }

            (amount0, amount1) = DyDxMath.getAmountsForLiquidity(
                uint256(priceLower),
                uint256(priceUpper),
                uint256(currentPrice),
                uint256(amount),
                false
            );
        }

        {
            // Ensure no overflow happens when we cast to int128.
            if (amount > uint128(type(int128).max)) revert Overflow();

            uint256 amount0fees;
            uint256 amount1fees;
            (amount0fees, amount1fees, oldLiquidity) = _updatePosition(msg.sender, lower, upper, -int128(amount));

            withdrawnAmounts = new TokenAmount[](2);
            withdrawnAmounts[0] = TokenAmount({token: token0, amount: amount0});
            withdrawnAmounts[1] = TokenAmount({token: token1, amount: amount1});

            feesWithdrawn = new TokenAmount[](2);
            withdrawnAmounts[0] = TokenAmount({token: token0, amount: amount0fees});
            withdrawnAmounts[1] = TokenAmount({token: token1, amount: amount1fees});

            unchecked {
                amount0 += amount0fees;
                amount1 += amount1fees;
            }
        }

        unchecked {
            reserve0 -= uint128(amount0);
            reserve1 -= uint128(amount1);
        }

        _transferBothTokens(recipient, amount0, amount1, unwrapBento);

        nearestTick = Ticks.remove(ticks, lower, upper, amount, nearestTick);
        emit Burn(msg.sender, amount0, amount1);
    }

    function burn(bytes calldata) public pure override returns (IPool.TokenAmount[] memory) {
        revert();
    }

    function burnSingle(bytes calldata) public pure override returns (uint256) {
        revert();
    }

    function collect(
        int24 lower,
        int24 upper,
        address recipient,
        bool unwrapBento
    ) public lock returns (uint256 amount0fees, uint256 amount1fees) {
        (amount0fees, amount1fees, ) = _updatePosition(msg.sender, lower, upper, 0);

        _transferBothTokens(recipient, amount0fees, amount1fees, unwrapBento);

        reserve0 -= uint128(amount0fees);
        reserve1 -= uint128(amount1fees);

        emit Collect(msg.sender, amount0fees, amount1fees);
    }

    /// @dev Swaps one token for another. The router must prefund this contract and ensure there isn't too much slippage
    /// - price is √(y/x)
    /// - x is token0
    /// - zero for one -> price will move down.
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

        unchecked {
            uint256 timestamp = block.timestamp;
            uint256 diff = timestamp - uint256(lastObservation); // Underflow in 2106. Don't do staking rewards in the year 2106.
            if (diff > 0 && liquidity > 0) {
                lastObservation = uint32(timestamp);
                secondsGrowthGlobal += uint160((diff << 128) / liquidity);
            }
        }

        while (cache.input != 0) {
            uint256 nextTickPrice = uint256(TickMath.getSqrtRatioAtTick(cache.nextTickToCross));
            uint256 output = 0;
            bool cross = false;

            if (zeroForOne) {
                // Trading token 0 (x) for token 1 (y).
                // Price is decreasing.
                // Maximum input amount within current tick range: Δx = Δ(1/√𝑃) · L.
                uint256 maxDx = DyDxMath.getDx(cache.currentLiquidity, nextTickPrice, cache.currentPrice, false);

                if (cache.input <= maxDx) {
                    // We can swap within the current range.
                    uint256 liquidityPadded = cache.currentLiquidity << 96;
                    // Calculate new price after swap: √𝑃[new] =  L · √𝑃 / (L + Δx · √𝑃)
                    // This is derrived from Δ(1/√𝑃) = Δx/L
                    // where Δ(1/√𝑃) is 1/√𝑃[old] - 1/√𝑃[new] and we solve for √𝑃[new].
                    // In case of an owerflow we can use: √𝑃[new] = L / (L / √𝑃 + Δx).
                    // This is derrived by dividing the original fraction by √𝑃 on both sides.
                    uint256 newPrice = uint256(
                        FullMath.mulDivRoundingUp(liquidityPadded, cache.currentPrice, liquidityPadded + cache.currentPrice * cache.input)
                    );

                    if (!(nextTickPrice <= newPrice && newPrice < cache.currentPrice)) {
                        // Overflow. We use a modified version of the formula.
                        newPrice = uint160(UnsafeMath.divRoundingUp(liquidityPadded, liquidityPadded / cache.currentPrice + cache.input));
                    }
                    // Based on the price difference calculate the output of th swap: Δy = Δ√P · L.
                    output = DyDxMath.getDy(cache.currentLiquidity, newPrice, cache.currentPrice, false);
                    cache.currentPrice = newPrice;
                    cache.input = 0;
                } else {
                    // Execute swap step and cross the tick.
                    output = DyDxMath.getDy(cache.currentLiquidity, nextTickPrice, cache.currentPrice, false);
                    cache.currentPrice = nextTickPrice;
                    cross = true;
                    cache.input -= maxDx;
                }
            } else {
                // Price is increasing.
                // Maximum swap amount within the current tick range: Δy = Δ√P · L.
                uint256 maxDy = DyDxMath.getDy(cache.currentLiquidity, cache.currentPrice, nextTickPrice, false);

                if (cache.input <= maxDy) {
                    // We can swap within the current range.
                    // Calculate new price after swap: ΔP = Δy/L.
                    uint256 newPrice = cache.currentPrice +
                        FullMath.mulDiv(cache.input, 0x1000000000000000000000000, cache.currentLiquidity);
                    // Calculate output of swap
                    // - Δx = Δ(1/√P) · L.
                    output = DyDxMath.getDx(cache.currentLiquidity, cache.currentPrice, newPrice, false);
                    cache.currentPrice = newPrice;
                    cache.input = 0;
                } else {
                    // Swap & cross the tick.
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
                    secondsGrowthGlobal,
                    cache.currentLiquidity,
                    cache.feeGrowthGlobal,
                    zeroForOne
                );
                if (cache.currentLiquidity == 0) {
                    // We step into a zone that has liquidity - or we reach the end of the linked list.
                    cache.currentPrice = uint256(TickMath.getSqrtRatioAtTick(cache.nextTickToCross));
                    (cache.currentLiquidity, cache.nextTickToCross) = Ticks.cross(
                        ticks,
                        cache.nextTickToCross,
                        secondsGrowthGlobal,
                        cache.currentLiquidity,
                        cache.feeGrowthGlobal,
                        zeroForOne
                    );
                }
            }
        }

        price = uint160(cache.currentPrice);

        int24 newNearestTick = zeroForOne ? cache.nextTickToCross : ticks[cache.nextTickToCross].previousTick;

        if (nearestTick != newNearestTick) {
            nearestTick = newNearestTick;
            liquidity = uint128(cache.currentLiquidity);
        }

        _updateReserves(zeroForOne, uint128(inAmount), amountOut);

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
    function flashSwap(bytes calldata) public pure override returns (uint256) {
        revert();
    }

    /// @dev Updates `barFee` for Trident protocol.
    function updateBarFee() public {
        barFee = IMasterDeployer(masterDeployer).barFee();
    }

    /// @dev Collects fees for Trident protocol.
    function collectProtocolFee() public lock returns (uint128 amount0, uint128 amount1) {
        if (token0ProtocolFee > 1) {
            amount0 = token0ProtocolFee - 1;
            token0ProtocolFee = 1;
            reserve0 -= amount0;
            _transfer(token0, amount0, barFeeTo, false);
        }
        if (token1ProtocolFee > 1) {
            amount1 = token1ProtocolFee - 1;
            token1ProtocolFee = 1;
            reserve1 -= amount1;
            _transfer(token1, amount1, barFeeTo, false);
        }
    }

    function _ensureTickSpacing(int24 lower, int24 upper) internal view {
        if (lower % int24(tickSpacing) != 0) revert InvalidTick();
        if ((lower / int24(tickSpacing)) % 2 != 0) revert LowerEven();
        if (upper % int24(tickSpacing) != 0) revert InvalidTick();
        if ((upper / int24(tickSpacing)) % 2 == 0) revert UpperOdd();
    }

    function _updateReserves(
        bool zeroForOne,
        uint128 inAmount,
        uint256 amountOut
    ) internal {
        if (zeroForOne) {
            uint256 balance0 = _balance(token0);
            uint128 newBalance = reserve0 + inAmount;
            if (uint256(newBalance) > balance0) revert Token0Missing();
            reserve0 = newBalance;
            reserve1 -= uint128(amountOut);
        } else {
            uint256 balance1 = _balance(token1);
            uint128 newBalance = reserve1 + inAmount;
            if (uint256(newBalance) > balance1) revert Token1Missing();
            reserve1 = newBalance;
            reserve0 -= uint128(amountOut);
        }
    }

    function _updateFees(
        bool zeroForOne,
        uint256 feeGrowthGlobal,
        uint128 protocolFee
    ) internal {
        if (zeroForOne) {
            feeGrowthGlobal1 = feeGrowthGlobal;
            token1ProtocolFee += protocolFee;
        } else {
            feeGrowthGlobal0 = feeGrowthGlobal;
            token0ProtocolFee += protocolFee;
        }
    }

    function _updatePosition(
        address owner,
        int24 lower,
        int24 upper,
        int128 amount
    )
        internal
        returns (
            uint256 amount0fees,
            uint256 amount1fees,
            uint256 oldLiquidity
        )
    {
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

        oldLiquidity = position.liquidity;

        if (amount < 0) {
            position.liquidity -= uint128(-amount);
        }

        if (amount > 0) {
            position.liquidity += uint128(amount);
            if (position.liquidity > MAX_TICK_LIQUIDITY) revert LiquidityOverflow();
        }

        position.feeGrowthInside0Last = growth0current;
        position.feeGrowthInside1Last = growth1current;
    }

    function _balance(address token) internal view returns (uint256 balance) {
        balance = bento.balanceOf(token, address(this));
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

    function _transferBothTokens(
        address to,
        uint256 shares0,
        uint256 shares1,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token0, address(this), to, 0, shares0);
            bento.withdraw(token1, address(this), to, 0, shares1);
        } else {
            bento.transfer(token0, address(this), to, shares0);
            bento.transfer(token1, address(this), to, shares1);
        }
    }

    /// @dev Generic formula for fee growth inside a range: (globalGrowth - growthBelow - growthAbove)
    /// - available counters: global, outside u, outside v.

    ///                  u         ▼         v
    /// ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - feeGrowthOutside(u) - feeGrowthOutside(v))

    ///             ▼    u                   v
    /// ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - (global - feeGrowthOutside(u)) - feeGrowthOutside(v))

    ///                  u                   v    ▼
    /// ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - feeGrowthOutside(u) - (global - feeGrowthOutside(v)))

    /// @notice Calculates the fee growth inside a range (per unit of liquidity).
    /// @dev Multiply `rangeFeeGrowth` delta by the provided liquidity to get accrued fees for some period.
    function rangeFeeGrowth(int24 lowerTick, int24 upperTick) public view returns (uint256 feeGrowthInside0, uint256 feeGrowthInside1) {
        int24 currentTick = nearestTick;

        Ticks.Tick storage lower = ticks[lowerTick];
        Ticks.Tick storage upper = ticks[upperTick];

        // Calculate fee growth below & above.
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

    function getAssets() public view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    /// @dev Reserved for IPool.
    function getAmountOut(bytes calldata) public pure override returns (uint256) {
        revert();
    }

    /// @dev Reserved for IPool.
    function getAmountIn(bytes calldata) public pure override returns (uint256) {
        revert();
    }

    function getImmutables()
        public
        view
        returns (
            uint128 _MAX_TICK_LIQUIDITY,
            uint24 _tickSpacing,
            uint24 _swapFee,
            address _barFeeTo,
            IBentoBoxMinimal _bento,
            IMasterDeployer _masterDeployer,
            address _token0,
            address _token1
        )
    {
        _MAX_TICK_LIQUIDITY = MAX_TICK_LIQUIDITY;
        _tickSpacing = tickSpacing;
        _swapFee = swapFee; // 1000 corresponds to 0.1% fee.
        _barFeeTo = barFeeTo;
        _bento = bento;
        _masterDeployer = masterDeployer;
        _token0 = token0;
        _token1 = token1;
    }

    function getPriceAndNearestTicks() public view returns (uint160 _price, int24 _nearestTick) {
        _price = price;
        _nearestTick = nearestTick;
    }

    function getTokenProtocolFees() public view returns (uint128 _token0ProtocolFee, uint128 _token1ProtocolFee) {
        _token0ProtocolFee = token0ProtocolFee;
        _token1ProtocolFee = token1ProtocolFee;
    }

    function getReserves() public view returns (uint128 _reserve0, uint128 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function getSecondsGrowthAndLastObservation() public view returns (uint160 _secondsGrowthGlobal, uint32 _lastObservation) {
        _secondsGrowthGlobal = secondsGrowthGlobal;
        _lastObservation = lastObservation;
    }
}

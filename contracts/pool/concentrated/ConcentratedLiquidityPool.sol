// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../../interfaces/IPool.sol";
import "../../interfaces/ITridentCallee.sol";
import "../../libraries/concentratedPool/TickMath.sol";
import "../../libraries/concentratedPool/FullMath.sol";
import "../../libraries/concentratedPool/UnsafeMath.sol";
import "../../libraries/concentratedPool/DyDxMath.sol";
import "hardhat/console.sol";

// TODO remove need for interface by calling the master deployer via low level calls
interface IMasterDeployer {
    function barFee() external view returns (uint256);

    function barFeeTo() external view returns (address);

    function bento() external view returns (address);
}

/// @notice Trident exchange pool template with concentrated liquidity and constant product formula for swapping between an ERC-20 token pair.
/// @dev The reserves are stored as bento shares.
///      The curve is applied to shares as well. This pool does not care about the underlying amounts.
contract ConcentratedLiquidityPool is IPool {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Collect(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserveShares0, uint256 reserveShares1);

    uint24 internal constant MAX_FEE = 10000; // @dev 100%.
    uint24 public immutable swapFee; // @dev 1000 corresponds to 0.1% fee.

    address public immutable barFeeTo;
    address public immutable bento;
    IMasterDeployer public immutable masterDeployer;
    address public immutable token0;
    address public immutable token1;

    uint160 public price; /// @dev sqrt of price aka. √(y/x), multiplied by 2^96.
    uint128 public liquidity;
    int24 public nearestTick; /// @dev Tick that is just below the current price.

    uint256 public feeGrowthGlobal0; /// @dev all fee growth counters are multiplied by 2^128
    uint256 public feeGrowthGlobal1;

    uint128 public reserve0; /// @dev Bento share balance tracker.
    uint128 public reserve1;

    uint160 public secondsPerLiquidity; /// @dev multiplied by 2^128
    uint32 public lastObservation;

    mapping(int24 => Tick) public ticks;
    mapping(address => mapping(int24 => mapping(int24 => Position))) public positions;

    struct Tick {
        int24 previousTick;
        int24 nextTick;
        uint128 liquidity;
        uint256 feeGrowthOutside0; // @dev Per unit of liquidity.
        uint256 feeGrowthOutside1;
        uint160 secondsPerLiquidityOutside;
    }

    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0Last;
        uint256 feeGrowthInside1Last;
        uint160 secondsPerLiquidityLast; // <- might want to store this in the manager contract only
    }

    /*
    univ3 1% -> 200 tickSpacing
    univ3 0.3% pool -> 60 tickSpacing -> 0.6% between ticks
    univ3 0.05% pool -> 10 tickSpacing -> 0.1% between ticks
    100 tickSpacing -> 1% between ticks => 2% between ticks on starting position (*stable pairs are different)
    */

    bytes32 public constant override poolIdentifier = "Trident:ConcentratedLiquidity";

    uint256 private unlocked;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, IMasterDeployer _masterDeployer) {
        (address _token0, address _token1, uint24 _swapFee, uint160 _price) = abi.decode(_deployData, (address, address, uint24, uint160));

        require(_token0 != address(0), "ZERO_ADDRESS");
        require(_token0 != _token1, "IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "INVALID_SWAP_FEE");

        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        price = _price;
        ticks[TickMath.MIN_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), 0, 0, 0);
        ticks[TickMath.MAX_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), 0, 0, 0);
        nearestTick = TickMath.MIN_TICK;
        bento = _masterDeployer.bento();
        barFeeTo = _masterDeployer.barFeeTo();
        masterDeployer = _masterDeployer;
        unlocked = 1;
    }

    function mint(bytes calldata data) public override lock returns (uint256 minted) {
        (int24 lowerOld, int24 lower, int24 upperOld, int24 upper, uint128 amount, address recipient) = abi.decode(
            data,
            (int24, int24, int24, int24, uint128, address)
        );

        uint160 priceLower = TickMath.getSqrtRatioAtTick(lower);
        uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);
        uint160 currentPrice = price;
        // @dev This is safe because overflow is checked in position minter contract.
        unchecked {
            if (priceLower < currentPrice && currentPrice < priceUpper) liquidity += amount;
        }
        // @dev Fees should have been claimed before position updates.
        _updatePosition(msg.sender, lower, upper, int128(amount));

        _insertInLinkedList(lowerOld, lower, upperOld, upper, amount, currentPrice);

        (uint128 amount0, uint128 amount1) = _getAmountsForLiquidity(
            uint256(priceLower),
            uint256(priceUpper),
            uint256(currentPrice),
            uint256(amount)
        );
        // @dev This is safe because overflow is checked in {getAmountsForLiquidity}.
        unchecked {
            if (amount0 != 0) {
                amount0 += reserve0;
                // @dev balanceOf(address,address).
                (, bytes memory _balance0) = bento.staticcall(abi.encodeWithSelector(0xf7888aec, token0, address(this)));
                uint256 balance0 = abi.decode(_balance0, (uint256));
                require(uint256(amount0) <= balance0, "TOKEN0_MISSING");
                // @dev `reserve0 = bento.balanceOf(...)` doesn't help anyone and coins will be stuck.
                reserve0 = amount0;
            }

            if (amount1 != 0) {
                amount1 += reserve1;
                // @dev balanceOf(address,address).
                (, bytes memory _balance1) = bento.staticcall(abi.encodeWithSelector(0xf7888aec, token1, address(this)));
                uint256 balance1 = abi.decode(_balance1, (uint256));
                require(uint256(amount1) <= balance1, "TOKEN1_MISSING");
                reserve1 = amount1;
            }
        }

        minted = amount;

        emit Mint(msg.sender, amount0, amount1, recipient);
    }

    function burn(bytes calldata data) public override lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (int24 lower, int24 upper, uint128 amount, address recipient, bool unwrapBento) = abi.decode(
            data,
            (int24, int24, uint128, address, bool)
        );

        uint160 priceLower = TickMath.getSqrtRatioAtTick(lower);
        uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);
        uint160 currentPrice = price;
        // @dev This is safe because user cannot have overflow amount of LP to burn.
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
        // @dev This is safe because overflow is checked in {updatePosition}.
        unchecked {
            amount0 += amount0fees;
            amount1 += amount1fees;
        }

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: token0, amount: amount0});
        withdrawnAmounts[1] = TokenAmount({token: token1, amount: amount1});

        _transfer(token0, amount0, recipient, unwrapBento);
        _transfer(token1, amount1, recipient, unwrapBento);

        _removeFromLinkedList(lower, upper, amount);

        emit Burn(msg.sender, amount0, amount1, recipient);
    }

    function burnSingle(bytes calldata) external override returns (uint256 amountOut) {
        // TODO
        return amountOut;
    }

    function collect(bytes calldata data) public lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (int24 lower, int24 upper, address recipient, bool unwrapBento) = abi.decode(data, (int24, int24, address, bool));

        (uint256 amount0fees, uint256 amount1fees) = _updatePosition(msg.sender, lower, upper, 0);

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: token0, amount: amount0fees});
        withdrawnAmounts[1] = TokenAmount({token: token1, amount: amount1fees});

        _transfer(token0, amount0fees, recipient, unwrapBento);
        _transfer(token1, amount1fees, recipient, unwrapBento);

        emit Collect(msg.sender, amount0fees, amount1fees);
    }

    struct SwapCache {
        uint256 feeAmount;
        uint256 totalFeeAmount;
        uint256 protocolFee;
        uint256 feeGrowthGlobal;
        int24 nextTickToCross;
        uint256 currentPrice;
        uint256 currentLiquidity;
        uint256 input;
    }

    /// @dev price is √(y/x)
    /// - x is token0
    /// - zero for one -> price will move down.
    function swap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (bool zeroForOne, uint256 inAmount, address recipient, bool unwrapBento) = abi.decode(data, (bool, uint256, address, bool));

        SwapCache memory cache = SwapCache({
            feeAmount: 0,
            totalFeeAmount: 0,
            protocolFee: 0,
            feeGrowthGlobal: zeroForOne ? feeGrowthGlobal1 : feeGrowthGlobal0,
            nextTickToCross: zeroForOne ? nearestTick : ticks[nearestTick].nextTick,
            currentPrice: uint256(price),
            currentLiquidity: uint256(liquidity),
            input: inAmount
        });

        {
            uint256 timestamp = block.timestamp;
            uint256 diff = timestamp - uint256(lastObservation); // gonna overflow in 2106 🤔
            if (diff > 0 && liquidity > 0) {
                // univ3 does max(liquidity, 1) 🤔
                lastObservation = uint32(timestamp);
                secondsPerLiquidity += uint160((diff << 128) / liquidity);
            }
        }

        while (cache.input != 0) {
            uint256 nextTickPrice = uint256(TickMath.getSqrtRatioAtTick(cache.nextTickToCross));
            uint256 output;
            bool cross = false;
            if (zeroForOne) {
                // @dev x for y
                // - price is going down
                // - max swap input within current tick range: Δx = Δ(1/√𝑃) · L.
                uint256 maxDx = DyDxMath.getDx(cache.currentLiquidity, nextTickPrice, cache.currentPrice, false);
                if (cache.input <= maxDx) {
                    // @dev We can swap only within the current range.
                    uint256 liquidityPadded = cache.currentLiquidity << 96;
                    /// @dev Calculate new price after swap: L · √𝑃 / (L + Δx · √𝑃)
                    // alternatively: L / (L / √𝑃 + Δx).
                    uint256 newPrice = uint256(
                        FullMath.mulDivRoundingUp(liquidityPadded, cache.currentPrice, liquidityPadded + cache.currentPrice * cache.input)
                    );

                    if (!(nextTickPrice <= newPrice && newPrice < cache.currentPrice)) {
                        // @dev Overflow -> use a modified version of the formula.
                        newPrice = uint160(UnsafeMath.divRoundingUp(liquidityPadded, liquidityPadded / cache.currentPrice + cache.input));
                    }
                    // @dev Calculate output of swap
                    // - Δy = Δ√P · L.
                    output = DyDxMath.getDy(cache.currentLiquidity, newPrice, cache.currentPrice, false);
                    cache.currentPrice = newPrice;
                    cache.input = 0;
                } else {
                    // @dev Swap & cross the tick.
                    output = DyDxMath.getDy(cache.currentLiquidity, nextTickPrice, cache.currentPrice, false);
                    cache.currentPrice = nextTickPrice;
                    cross = true;
                    cache.input -= maxDx;
                }
            } else {
                // @dev Price is going up
                // - max swap within current tick range: Δy = Δ√P · L.
                uint256 maxDy = DyDxMath.getDy(cache.currentLiquidity, cache.currentPrice, nextTickPrice, false);
                if (cache.input <= maxDy) {
                    // @dev We can swap only within the current range
                    // - calculate new price after swap ( ΔP = Δy/L ).
                    uint256 newPrice = cache.currentPrice +
                        FullMath.mulDiv(cache.input, 0x1000000000000000000000000, cache.currentLiquidity);
                    // @dev Calculate output of swap
                    // - Δx = Δ(1/√P) · L.
                    output = DyDxMath.getDx(cache.currentLiquidity, cache.currentPrice, newPrice, false);
                    cache.currentPrice = newPrice;
                    cache.input = 0;
                } else {
                    // @dev Swap & cross the tick.
                    output = DyDxMath.getDx(cache.currentLiquidity, cache.currentPrice, nextTickPrice, false);
                    cache.currentPrice = nextTickPrice;
                    cross = true;
                    cache.input -= maxDy;
                }
            }

            cache.feeAmount = FullMath.mulDivRoundingUp(output, swapFee, 1e6);

            // @dev Calculate `protocolFee` and convert pips to bips
            // - stack too deep when trying to store this in a variable
            // - NB can get optimized after we put things into structs.
            cache.protocolFee += FullMath.mulDivRoundingUp(cache.feeAmount, masterDeployer.barFee(), 1e4);

            // @dev Updating `feeAmount` based on the protocolFee.
            cache.feeAmount -= FullMath.mulDivRoundingUp(cache.feeAmount, masterDeployer.barFee(), 1e4);

            cache.feeGrowthGlobal += FullMath.mulDiv(cache.feeAmount, 0x100000000000000000000000000000000, cache.currentLiquidity);

            amountOut += output - cache.feeAmount;

            if (cross) {
                ticks[cache.nextTickToCross].secondsPerLiquidityOutside =
                    secondsPerLiquidity -
                    ticks[cache.nextTickToCross].secondsPerLiquidityOutside;
                if (zeroForOne) {
                    // Going left.
                    if (cache.nextTickToCross % 2 == 0) {
                        cache.currentLiquidity -= ticks[cache.nextTickToCross].liquidity;
                    } else {
                        cache.currentLiquidity += ticks[cache.nextTickToCross].liquidity;
                    }
                    cache.nextTickToCross = ticks[cache.nextTickToCross].previousTick;
                    ticks[cache.nextTickToCross].feeGrowthOutside0 = cache.feeGrowthGlobal - ticks[cache.nextTickToCross].feeGrowthOutside0;
                } else {
                    // Going right.
                    if (cache.nextTickToCross % 2 == 0) {
                        cache.currentLiquidity += ticks[cache.nextTickToCross].liquidity;
                    } else {
                        cache.currentLiquidity -= ticks[cache.nextTickToCross].liquidity;
                    }
                    cache.nextTickToCross = ticks[cache.nextTickToCross].nextTick;
                    ticks[cache.nextTickToCross].feeGrowthOutside1 = cache.feeGrowthGlobal - ticks[cache.nextTickToCross].feeGrowthOutside1;
                }
            }
        }

        price = uint160(cache.currentPrice);

        int24 newNearestTick = zeroForOne ? cache.nextTickToCross : ticks[cache.nextTickToCross].previousTick;

        if (nearestTick != newNearestTick) {
            nearestTick = newNearestTick;
            liquidity = uint128(cache.currentLiquidity);
        }

        (uint256 amount0, uint256 amount1) = _balance();

        if (zeroForOne) {
            feeGrowthGlobal0 += cache.feeGrowthGlobal;
            uint128 newBalance = reserve0 + uint128(inAmount);
            require(uint256(newBalance) <= amount0, "TOKEN0_MISSING");
            reserve0 = newBalance;
            reserve1 -= (uint128(amountOut) + uint128(cache.feeAmount) + uint128(cache.protocolFee));
            // @dev Transfer fees to bar.
            _transfer(token1, cache.protocolFee, barFeeTo, false);
            _transfer(token1, amountOut, recipient, unwrapBento);
            emit Swap(recipient, token0, token1, inAmount, amountOut);
        } else {
            feeGrowthGlobal0 += cache.feeGrowthGlobal;
            uint128 newBalance = reserve1 + uint128(inAmount);
            require(uint256(newBalance) <= amount1, "TOKEN1_MISSING");
            reserve1 = newBalance;
            reserve0 -= (uint128(amountOut) + uint128(cache.feeAmount) + uint128(cache.protocolFee));
            // @dev Transfer fees to bar.
            _transfer(token0, cache.protocolFee, barFeeTo, false);
            _transfer(token0, amountOut, recipient, unwrapBento);
            emit Swap(recipient, token1, token0, inAmount, amountOut);
        }
    }

    function flashSwap(bytes calldata) external override returns (uint256 finalAmountOut) {
        // TODO
        return finalAmountOut;
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        // @dev balanceOf(address,address).
        (, bytes memory _balance0) = bento.staticcall(abi.encodeWithSelector(0xf7888aec, token0, address(this)));
        balance0 = abi.decode(_balance0, (uint256));
        // @dev balanceOf(address,address).
        (, bytes memory _balance1) = bento.staticcall(abi.encodeWithSelector(0xf7888aec, token1, address(this)));
        balance1 = abi.decode(_balance1, (uint256));
    }

    function _transfer(
        address token,
        uint256 shares,
        address to,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            // @dev withdraw(address,address,address,uint256,uint256).
            (bool success, ) = bento.call(abi.encodeWithSelector(0x97da6d30, token, address(this), to, 0, shares));
            require(success, "WITHDRAW_FAILED");
        } else {
            // @dev transfer(address,address,address,uint256).
            (bool success, ) = bento.call(abi.encodeWithSelector(0xf18d03cc, token, address(this), to, shares));
            require(success, "TRANSFER_FAILED");
        }
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

    function _insertInLinkedList(
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint128 amount,
        uint160 currentPrice
    ) internal {
        require(uint24(lower) % 2 == 0, "LOWER_EVEN");
        require(uint24(upper) % 2 == 1, "UPPER_ODD");

        require(lower < upper, "WRONG_ORDER");

        require(TickMath.MIN_TICK <= lower && lower < TickMath.MAX_TICK, "LOWER_RANGE");
        require(TickMath.MIN_TICK < upper && upper <= TickMath.MAX_TICK, "UPPER_RANGE");

        int24 currentNearestTick = nearestTick;

        if (ticks[lower].liquidity != 0 || lower == TickMath.MIN_TICK) {
            // @dev We are adding liquidity to an existing tick.
            ticks[lower].liquidity += amount;
        } else {
            // @dev Inserting a new tick.
            Tick storage old = ticks[lowerOld];

            require((old.liquidity != 0 || lowerOld == TickMath.MIN_TICK) && lowerOld < lower && lower < old.nextTick, "LOWER_ORDER");

            if (lower <= currentNearestTick) {
                ticks[lower] = Tick(lowerOld, old.nextTick, amount, feeGrowthGlobal0, feeGrowthGlobal1, secondsPerLiquidity);
            } else {
                ticks[lower] = Tick(lowerOld, old.nextTick, amount, 0, 0, 0);
            }

            old.nextTick = lower;
        }

        if (ticks[upper].liquidity != 0 || upper == TickMath.MAX_TICK) {
            // @dev We are adding liquidity to an existing tick.
            ticks[upper].liquidity += amount;
        } else {
            // @dev Inserting a new tick.
            Tick storage old = ticks[upperOld];

            require(old.liquidity != 0 && old.nextTick > upper && upperOld < upper, "UPPER_ORDER");

            if (upper <= currentNearestTick) {
                ticks[upper] = Tick(upperOld, old.nextTick, amount, feeGrowthGlobal0, feeGrowthGlobal1, secondsPerLiquidity);
            } else {
                ticks[upper] = Tick(upperOld, old.nextTick, amount, 0, 0, 0);
            }

            old.nextTick = upper;
        }

        int24 actualNearestTick = TickMath.getTickAtSqrtRatio(currentPrice);

        if (currentNearestTick < lower && lower <= actualNearestTick) currentNearestTick = lower;

        if (currentNearestTick < upper && upper <= actualNearestTick) currentNearestTick = upper;

        nearestTick = currentNearestTick;
    }

    function _removeFromLinkedList(
        int24 lower,
        int24 upper,
        uint128 amount
    ) internal {
        Tick storage current = ticks[lower];

        if (lower != TickMath.MIN_TICK && current.liquidity == amount) {
            /// @dev Delete lower tick.
            Tick storage previous = ticks[current.previousTick];
            Tick storage next = ticks[current.nextTick];

            previous.nextTick = current.nextTick;
            next.previousTick = current.previousTick;

            if (nearestTick == lower) nearestTick = current.previousTick;

            delete ticks[lower];
        } else {
            current.liquidity -= amount;
        }

        current = ticks[upper];

        if (upper != TickMath.MAX_TICK && current.liquidity == amount) {
            // @dev Delete upper tick.
            Tick storage previous = ticks[current.previousTick];
            Tick storage next = ticks[current.nextTick];

            previous.nextTick = current.nextTick;
            next.previousTick = current.previousTick;

            if (nearestTick == upper) nearestTick = current.previousTick;

            delete ticks[upper];
        } else {
            current.liquidity -= amount;
        }
    }

    // Generic formula for fee growth inside a range: (globalGrowth - growthBelow - growthAbove)
    // Available counters: global, outside u, outside v

    //                  u         ▼         v
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - feeGrowthOutside(u) - feeGrowthOutside(v))

    //             ▼    u                   v
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - (global - feeGrowthOutside(u)) - feeGrowthOutside(v))

    //                  u                   v    ▼
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|--------- (global - feeGrowthOutside(u) - (global - feeGrowthOutside(v)))

    /// @notice Calculates the fee growth inside a range (per unit of liquidity).
    /// @dev Multiply rangeFeeGrowth delta by the provided liquidity to get accrued fees for some period.
    function rangeFeeGrowth(int24 lowerTick, int24 upperTick) public view returns (uint256 feeGrowthInside0, uint256 feeGrowthInside1) {
        int24 currentTick = nearestTick;

        Tick storage lower = ticks[lowerTick];
        Tick storage upper = ticks[upperTick];

        // @dev Calculate fee growth below & above.
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

        Tick storage lower = ticks[lowerTick];
        Tick storage upper = ticks[upperTick];

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

    function getAmountOut(bytes calldata) public view override returns (uint256 finalAmountOut) {
        // TODO
        return finalAmountOut;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/concentratedPool/TickMath.sol";
import "../libraries/concentratedPool/FullMath.sol";
import "../libraries/concentratedPool/UnsafeMath.sol";
import "../libraries/concentratedPool/DyDxMath.sol";
import "hardhat/console.sol";

contract Cpcp {
    struct Tick {
        int24 previousTick;
        int24 nextTick;
        uint128 liquidity;
        uint256 feeGrowthOutside0X128; // per unit of liquidity
        uint256 feeGrowthOutside1X128;
    }

    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
    }

    IERC20 public immutable token0;

    IERC20 public immutable token1;

    uint24 public immutable fee; // 1000 corresponds to 0.1% fee

    mapping(int24 => Tick) public ticks;

    mapping(address => mapping(int24 => mapping(int24 => Position))) public positions;

    uint128 public liquidity;

    uint160 public price; // sqrt of price, multiplied by 2^96

    int24 public nearestTick; // tick that is just bellow the current price

    uint256 public feeGrowthGlobal0X128;

    uint256 public feeGrowthGlobal1X128;

    uint128 private reserve0;

    uint128 private reserve1;

    constructor(bytes memory deployData) {
        (IERC20 _token0, IERC20 _token1, uint160 _price, uint24 _fee) = abi.decode(
            deployData,
            (IERC20, IERC20, uint160, uint24)
        );

        token0 = _token0;

        token1 = _token1;

        price = _price;

        fee = _fee;

        ticks[TickMath.MIN_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), 0, 0);

        ticks[TickMath.MAX_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), 0, 0);

        nearestTick = TickMath.MIN_TICK;
    }

    function mint(
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint128 amount,
        address recipient
    ) public {
        uint160 priceLower = TickMath.getSqrtRatioAtTick(lower);

        uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);

        uint160 currentPrice = price;

        if (priceLower < currentPrice && currentPrice < priceUpper) liquidity += amount;

        setPosition(recipient, lower, upper, int128(amount));

        updateLinkedList(lowerOld, lower, upperOld, upper, amount, currentPrice);

        getAssets(uint256(priceLower), uint256(priceUpper), uint256(currentPrice), uint256(amount));
    }

    // price is √(y/x)
    // x is token0
    // zero for one -> price will move down
    function swap(
        bool zeroForOne,
        uint256 inAmount,
        address recipient
    ) public {
        int24 nextTickToCross = zeroForOne ? nearestTick : ticks[nearestTick].nextTick;

        uint256 currentPrice = uint256(price);

        uint256 currentLiquidity = uint256(liquidity);

        uint256 outAmount = 0;

        uint256 input = inAmount;

        uint256 feeGrowthGlobal = zeroForOne ? feeGrowthGlobal1X128 : feeGrowthGlobal0X128; // take fees in the ouput token

        while (input > 0) {
            uint256 nextTickPrice = uint256(TickMath.getSqrtRatioAtTick(nextTickToCross));

            uint256 output = 0;

            uint256 feeAmount = 0;

            bool cross = false;

            if (zeroForOne) {
                // x for y

                // price is going down
                // max swap input within current tick range: Δx = Δ(1/√𝑃) · L

                uint256 maxDx = DyDxMath.getDx(currentLiquidity, nextTickPrice, currentPrice, false);

                if (input <= maxDx) {
                    // we can swap only within the current range

                    uint256 liquidityPadded = currentLiquidity << 96;

                    // calculate new price after swap: L · √𝑃 / (L + Δx · √𝑃)
                    // alternatively: L / (L / √𝑃 + Δx)

                    uint256 newPrice = uint160(
                        FullMath.mulDivRoundingUp(liquidityPadded, currentPrice, liquidityPadded + currentPrice * input)
                    );

                    if (!(nextTickPrice <= newPrice && newPrice < currentPrice)) {
                        // overflow -> use a modified version of the formula
                        newPrice = uint160(
                            UnsafeMath.divRoundingUp(liquidityPadded, liquidityPadded / currentPrice + input)
                        );
                    }

                    // calculate output of swap
                    // Δy = Δ√P · L
                    output = DyDxMath.getDy(currentLiquidity, newPrice, currentPrice, false);

                    currentPrice = newPrice;

                    input = 0;
                } else {
                    // swap & cross the tick

                    output = DyDxMath.getDy(currentLiquidity, nextTickPrice, currentPrice, false);

                    currentPrice = nextTickPrice;

                    cross = true;

                    input -= maxDx;
                }
            } else {
                // price is going up
                // max swap within current tick range: Δy = Δ√P · L

                uint256 maxDy = DyDxMath.getDy(currentLiquidity, currentPrice, nextTickPrice, false);

                if (input <= maxDy) {
                    // we can swap only within the current range

                    // calculate new price after swap ( ΔP = Δy/L )
                    uint256 newPrice = currentPrice +
                        FullMath.mulDiv(input, 0x1000000000000000000000000, currentLiquidity);

                    // calculate output of swap
                    // Δx = Δ(1/√P) · L
                    output = DyDxMath.getDx(currentLiquidity, currentPrice, newPrice, false);

                    currentPrice = newPrice;

                    input = 0;
                } else {
                    // swap & cross the tick

                    output = DyDxMath.getDx(currentLiquidity, currentPrice, nextTickPrice, false);

                    currentPrice = nextTickPrice;

                    cross = true;

                    input -= maxDy;
                }
            }

            feeAmount = FullMath.mulDivRoundingUp(output, fee, 1e6);

            feeGrowthGlobal += FullMath.mulDiv(feeAmount, 0x100000000000000000000000000000000, currentLiquidity);

            outAmount += output - feeAmount;

            if (cross) {
                ticks[nextTickToCross].feeGrowthOutside0X128 =
                    feeGrowthGlobal -
                    ticks[nextTickToCross].feeGrowthOutside0X128;

                if (zeroForOne) {
                    // goin' left
                    if (nextTickToCross % 2 == 0) {
                        currentLiquidity -= ticks[nextTickToCross].liquidity;
                    } else {
                        currentLiquidity += ticks[nextTickToCross].liquidity;
                    }

                    nextTickToCross = ticks[nextTickToCross].previousTick;
                } else {
                    // goin' right
                    if (nextTickToCross % 2 == 0) {
                        currentLiquidity += ticks[nextTickToCross].liquidity;
                    } else {
                        currentLiquidity -= ticks[nextTickToCross].liquidity;
                    }

                    nextTickToCross = ticks[nextTickToCross].nextTick;
                }
            }
        }

        liquidity = uint128(currentLiquidity);

        price = uint160(currentPrice);

        nearestTick = zeroForOne ? nextTickToCross : ticks[nextTickToCross].previousTick;

        if (zeroForOne) {
            uint128 newBalance = reserve0 + uint128(inAmount);
            require(uint256(newBalance) <= token0.balanceOf(address(this)), "Missing x deposit");
            reserve0 = newBalance;
            reserve1 -= uint128(outAmount);
            token1.transfer(recipient, outAmount);
        } else {
            uint128 newBalance = reserve1 + uint128(inAmount);
            require(uint256(newBalance) <= token1.balanceOf(address(this)), "Missing y deposit");
            reserve1 = newBalance;
            reserve0 -= uint128(outAmount);
            token0.transfer(recipient, outAmount);
        }

        // emit event
    }

    //                  u         ▼         v
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------

    //             ▼    u                   v
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------

    //                  u                   v    ▼
    // ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------

    // fees: global, outside u, outside v - we are interested in the 'xxxx' zone

    function getFeeGrowthInside(int24 lowerTick, int24 upperTick)
        public
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        int24 currentTick = nearestTick;

        Tick storage lower = ticks[lowerTick];
        Tick storage upper = ticks[upperTick];

        // calculate fee growth below & above
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;

        if (lowerTick <= currentTick) {
            feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
        }

        if (currentTick < upperTick) {
            feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    function getAssets(
        uint256 priceLower,
        uint256 priceUpper,
        uint256 currentPrice,
        uint256 liquidityAmount
    ) internal {
        uint128 token0amount = 0;
        uint128 token1amount = 0;

        if (priceUpper <= currentPrice) {
            // only supply token1 (token1 is Y)

            token1amount = uint128(DyDxMath.getDy(liquidityAmount, priceLower, priceUpper, true));
        } else if (currentPrice <= priceLower) {
            // only supply token0 (token0 is X)

            token0amount = uint128(DyDxMath.getDx(liquidityAmount, priceLower, priceUpper, true));
        } else {
            // supply both tokens

            token0amount = uint128(DyDxMath.getDx(liquidityAmount, currentPrice, priceUpper, true));

            token1amount = uint128(DyDxMath.getDy(liquidityAmount, priceLower, currentPrice, true));
        }

        if (token0amount > 0) {
            token0amount += reserve0;
            require(uint256(token0amount) <= token0.balanceOf(address(this)), "Didn't deposit token0"); // ! change this to bento shares
            reserve0 = token0amount;
            /** @dev `reserve0 = token0.balanceOf(address(this))`
                    doesn't help anyone as coins will be stuck */
        }

        if (token1amount > 0) {
            token1amount += reserve1;
            require(uint256(token1amount) <= token1.balanceOf(address(this)), "Didn't deposit token1"); // ! change this to bento shares
            reserve1 = token1amount;
        }
    }

    function updateLinkedList(
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint128 amount,
        uint160 currentPrice
    ) internal {
        require(uint24(lower) % 2 == 0, "Lower even");
        require(uint24(upper) % 2 == 1, "Upper odd");

        require(lower < upper, "Order");

        require(TickMath.MIN_TICK <= lower && lower < TickMath.MAX_TICK, "Lower range");
        require(TickMath.MIN_TICK < upper && upper <= TickMath.MAX_TICK, "Upper range");

        int24 currentNearestTick = nearestTick;

        if (ticks[lower].liquidity > 0 || lower == TickMath.MIN_TICK) {
            // we are adding liquidity to an existing tick

            ticks[lower].liquidity += amount;
        } else {
            // inserting a new tick

            Tick storage old = ticks[lowerOld];

            require(
                (old.liquidity > 0 || lowerOld == TickMath.MIN_TICK) && lowerOld < lower && lower < old.nextTick,
                "Lower order"
            );

            if (lower <= currentNearestTick) {
                ticks[lower] = Tick(lowerOld, old.nextTick, amount, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
            } else {
                ticks[lower] = Tick(lowerOld, old.nextTick, amount, 0, 0);
            }

            old.nextTick = lower;
        }

        if (ticks[upper].liquidity > 0 || upper == TickMath.MAX_TICK) {
            // we are adding liquidity to an existing tick

            ticks[upper].liquidity += amount;
        } else {
            // inserting a new tick
            Tick storage old = ticks[upperOld];

            require(old.liquidity > 0 && old.nextTick > upper && upperOld < upper, "Upper order");

            if (upper <= currentNearestTick) {
                ticks[upper] = Tick(upperOld, old.nextTick, amount, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
            } else {
                ticks[upper] = Tick(upperOld, old.nextTick, amount, 0, 0);
            }

            old.nextTick = upper;
        }

        int24 actualNearestTick = TickMath.getTickAtSqrtRatio(currentPrice);

        if (currentNearestTick < lower && lower <= actualNearestTick) currentNearestTick = lower;

        if (currentNearestTick < upper && upper <= actualNearestTick) currentNearestTick = upper;

        nearestTick = currentNearestTick;
    }

    function setPosition(
        address recipient,
        int24 lower,
        int24 upper,
        int128 amount
    ) internal {
        Position storage position = positions[recipient][lower][upper];
        if (amount < 0) position.liquidity -= uint128(amount);
        if (amount > 0) position.liquidity += uint128(amount);
    }
}

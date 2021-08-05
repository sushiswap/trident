// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/concentratedPool/TickMath.sol";
import "../libraries/concentratedPool/FullMath.sol";
import "../libraries/concentratedPool/UnsafeMath.sol";
import "../libraries/concentratedPool/DyDxMath.sol";
import "hardhat/console.sol";

pragma solidity ^0.8.2;

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
        uint256 feeGrowthInside0LastX128; // per unit of liquidity
        uint256 feeGrowthInside1LastX128;
    }

    mapping(int24 => Tick) public ticks;

    mapping(address => mapping(int24 => mapping(int24 => Position))) public positions;

    uint128 public liquidity;

    uint160 public price; // sqrt of price, multiplied by 2^96

    int24 public nearestTick; // tick that is just bellow the current price

    IERC20 public token0;

    IERC20 public token1;

    uint256 public feeGrowthGlobal0X128;

    uint256 public feeGrowthGlobal1X128;

    uint256 public fee = 1000; // 0.1% fee

    constructor(bytes memory deployData) {
        (IERC20 _token0, IERC20 _token1, uint160 _price) = abi.decode(deployData, (IERC20, IERC20, uint160));

        token0 = _token0;

        token1 = _token1;

        price = _price;

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

        storePosition(recipient, lower, upper, amount);

        updateLinkedList(lowerOld, lower, upperOld, upper, amount, currentPrice);

        getAssets(uint256(priceLower), uint256(priceUpper), uint256(currentPrice), uint256(amount));
    }

    function getAssets(
        uint256 priceLower,
        uint256 priceUpper,
        uint256 currentPrice,
        uint256 liquidityAmount
    ) internal {
        uint256 token0amount = 0;

        uint256 token1amount = 0;

        if (priceUpper <= currentPrice) {
            // only supply token1 (token1 is Y)

            token1amount = DyDxMath.getDy(liquidityAmount, priceLower, priceUpper, true);
        } else if (currentPrice <= priceLower) {
            // only supply token0 (token0 is X)

            token0amount = DyDxMath.getDx(liquidityAmount, priceLower, priceUpper, true);
        } else {
            // supply both tokens

            token0amount = DyDxMath.getDx(liquidityAmount, currentPrice, priceUpper, true);

            token1amount = DyDxMath.getDy(liquidityAmount, priceLower, currentPrice, true);
        }

        if (token0amount > 0) token0.transferFrom(msg.sender, address(this), token0amount); // ! change this to bento shares

        if (token1amount > 0) token1.transferFrom(msg.sender, address(this), token1amount);
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

            if (lower <= currentNearestTick) {
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

    function storePosition(
        address recipient,
        int24 lower,
        int24 upper,
        uint128 amount
    ) internal {
        Position storage position = positions[recipient][lower][upper];

        // todo
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
                if (zeroForOne) {
                    if (nextTickToCross % 2 == 0) {
                        currentLiquidity -= ticks[nextTickToCross].liquidity;
                    } else {
                        currentLiquidity += ticks[nextTickToCross].liquidity;
                    }

                    nextTickToCross = ticks[nextTickToCross].previousTick;
                } else {
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
            token0.transferFrom(msg.sender, address(this), inAmount); // ! change this to bento shares, a push / pull approach instead
            token1.transfer(recipient, outAmount);
        } else {
            token1.transferFrom(msg.sender, address(this), inAmount); // ! change this to bento shares, a push / pull approach instead
            token0.transfer(recipient, outAmount);
        }

        // emit event
    }
}

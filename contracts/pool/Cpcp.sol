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
    }

    mapping(int24 => Tick) public ticks;

    uint128 public liquidity;

    uint160 public sqrtPriceX96;

    int24 public nearestTick; // tick that is just bellow the current price

    IERC20 public token0;

    IERC20 public token1;

    constructor(bytes memory deployData) {
        (IERC20 _token0, IERC20 _token1, uint160 _sqrtPriceX96) = abi.decode(deployData, (IERC20, IERC20, uint160));

        token0 = _token0;

        token1 = _token1;

        sqrtPriceX96 = _sqrtPriceX96;

        ticks[TickMath.MIN_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0));

        ticks[TickMath.MAX_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0));

        nearestTick = TickMath.MIN_TICK;
    }

    function mint(
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint128 amount
    ) public {
        uint160 priceLower = TickMath.getSqrtRatioAtTick(lower);

        uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);

        uint160 currentPrice = sqrtPriceX96;

        if (priceLower < currentPrice && currentPrice < priceUpper) liquidity += amount;

        updateLinkedList(lowerOld, lower, upperOld, upper, amount);

        updateNearestTickPointer(lower, upper, nearestTick, currentPrice);

        getAssets(uint256(priceLower), uint256(priceUpper), uint256(currentPrice), uint256(amount));
    }

    function getAssets(
        uint256 priceLower,
        uint256 priceUpper,
        uint256 _sqrtPriceX96,
        uint256 liquidityAmount
    ) internal {
        uint256 token0amount = 0;

        uint256 token1amount = 0;

        if (priceUpper < _sqrtPriceX96) {
            // think about edgecases here <= vs <
            // only supply token1 (token1 is Y)

            token1amount = DyDxMath.getDy(liquidityAmount, priceLower, priceUpper, true);
        } else if (_sqrtPriceX96 < priceLower) {
            // only supply token0 (token0 is X)

            token0amount = DyDxMath.getDx(liquidityAmount, priceLower, priceUpper, true);
        } else {
            // supply both tokens

            token0amount = DyDxMath.getDx(liquidityAmount, _sqrtPriceX96, priceUpper, true);

            token1amount = DyDxMath.getDy(liquidityAmount, priceLower, _sqrtPriceX96, true);
        }

        if (token0amount > 0) token0.transferFrom(msg.sender, address(this), token0amount); // ! change this to bento shares

        if (token1amount > 0) token1.transferFrom(msg.sender, address(this), token1amount);
    }

    function updateNearestTickPointer(
        int24 lower,
        int24 upper,
        int24 currentNearestTick,
        uint160 _sqrtPriceX96
    ) internal {
        int24 actualNearestTick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);

        if (currentNearestTick < lower && lower <= actualNearestTick) currentNearestTick = lower;

        if (currentNearestTick < upper && upper <= actualNearestTick) currentNearestTick = upper;

        nearestTick = currentNearestTick;
    }

    function updateLinkedList(
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint128 amount
    ) internal {
        require(uint24(lower) % 2 == 0, "Lower even");
        require(uint24(upper) % 2 == 1, "Upper odd");

        require(lower < upper, "Order");

        require(TickMath.MIN_TICK <= lower && lower < TickMath.MAX_TICK, "Lower range");
        require(TickMath.MIN_TICK < upper && upper <= TickMath.MAX_TICK, "Upper range");

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

            ticks[lower] = Tick(lowerOld, old.nextTick, amount);

            old.nextTick = lower;
        }

        if (ticks[upper].liquidity > 0 || upper == TickMath.MAX_TICK) {
            // we are adding liquidity to an existing tick

            ticks[upper].liquidity += amount;
        } else {
            // inserting a new tick
            Tick storage old = ticks[upperOld];

            require(old.liquidity > 0 && old.nextTick > upper && upperOld < upper, "Upper order");

            ticks[upper] = Tick(upperOld, old.nextTick, amount);

            old.nextTick = upper;
        }
    }

    // price is √(y/x)
    // x is token0
    // zero for one -> price will move down
    function swap(
        bool zeroForOne,
        uint256 amount,
        address recipient
    ) public {
        int24 nextTickToCross = zeroForOne ? nearestTick : ticks[nearestTick].nextTick;

        uint256 currentPrice = uint256(sqrtPriceX96);

        uint256 currentLiquidity = uint256(liquidity);

        uint256 outAmount = 0;

        uint256 inAmount = amount;

        while (amount > 0) {
            uint256 nextTickPrice = uint256(TickMath.getSqrtRatioAtTick(nextTickToCross));

            if (zeroForOne) {
                // x for y

                // price is going down
                // max swap input within current tick range: Δx = Δ(1/√𝑃) · L

                uint256 maxDx = DyDxMath.getDx(currentLiquidity, nextTickPrice, currentPrice, false);

                if (amount <= maxDx) {
                    // we can swap only within the current range

                    uint256 liquidityPadded = currentLiquidity << 96;

                    // calculate new price after swap: L · √𝑃 / (L + Δx · √𝑃)
                    // alternatively: L / (L / √𝑃 + Δx)

                    uint256 newPrice = uint160(
                        FullMath.mulDivRoundingUp(
                            liquidityPadded,
                            currentPrice,
                            liquidityPadded + currentPrice * amount
                        )
                    );

                    if (!(nextTickPrice <= newPrice && newPrice < currentPrice)) {
                        // owerflow -> use a modified version of the formula
                        newPrice = uint160(
                            UnsafeMath.divRoundingUp(liquidityPadded, liquidityPadded / currentPrice + amount)
                        );
                    }

                    // calculate output of swap
                    // Δy = Δ√P · L
                    outAmount += DyDxMath.getDy(currentLiquidity, newPrice, currentPrice, false);

                    amount = 0;

                    currentPrice = newPrice;
                } else {
                    // swap & cross the tick

                    amount -= maxDx;

                    outAmount += DyDxMath.getDy(currentLiquidity, nextTickPrice, currentPrice, false);

                    if (nextTickToCross % 2 == 0) {
                        currentLiquidity = currentLiquidity - uint256(ticks[nextTickToCross].liquidity);
                    } else {
                        currentLiquidity = currentLiquidity + uint256(ticks[nextTickToCross].liquidity);
                    }

                    currentPrice = nextTickPrice;

                    nextTickToCross = ticks[nextTickToCross].previousTick;
                }
            } else {
                // price is going up
                // max swap within current tick range: Δy = Δ√P · L

                uint256 maxDy = DyDxMath.getDy(currentLiquidity, currentPrice, nextTickPrice, false);

                if (amount <= maxDy) {
                    // we can swap only within the current range

                    // calculate new price after swap ( ΔP = Δy/L )
                    uint256 newPrice;

                    if (amount <= type(uint160).max) {
                        newPrice = currentPrice + (amount << 96) / currentLiquidity;
                    } else {
                        newPrice =
                            currentPrice +
                            uint160(FullMath.mulDiv(amount, 0x1000000000000000000000000, liquidity));
                    }

                    // calculate output of swap
                    // Δx = Δ(1/√P) · L
                    outAmount += DyDxMath.getDx(currentLiquidity, currentPrice, newPrice, false);

                    amount = 0;

                    currentPrice = newPrice;
                } else {
                    // swap & cross the tick

                    amount -= maxDy;

                    outAmount += DyDxMath.getDx(currentLiquidity, currentPrice, nextTickPrice, false);

                    if (nextTickToCross % 2 == 0) {
                        currentLiquidity = currentLiquidity + uint256(ticks[nextTickToCross].liquidity);
                    } else {
                        currentLiquidity = currentLiquidity - uint256(ticks[nextTickToCross].liquidity);
                    }

                    currentPrice = nextTickPrice;

                    nextTickToCross = ticks[nextTickToCross].nextTick;
                }
            }
        }

        liquidity = uint128(currentLiquidity);

        sqrtPriceX96 = uint160(currentPrice);

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

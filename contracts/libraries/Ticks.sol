// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "./TickMath.sol";
import "../interfaces/IConcentratedLiquidityPool.sol";

/// @notice Tick management library for ranged liquidity.
library Ticks {
    function getMaxLiquidity(uint24 _tickSpacing) public pure returns (uint128) {
        return type(uint128).max / uint128(uint24(TickMath.MAX_TICK) / (2 * uint24(_tickSpacing)));
    }

    function cross(
        mapping(int24 => IConcentratedLiquidityPoolStruct.Tick) storage ticks,
        int24 nextTickToCross,
        uint160 secondsGrowthGlobal,
        uint256 currentLiquidity,
        uint256 feeGrowthGlobalA,
        uint256 feeGrowthGlobalB,
        bool zeroForOne,
        uint24 tickSpacing
    ) internal returns (uint256, int24) {
        ticks[nextTickToCross].secondsGrowthOutside = secondsGrowthGlobal - ticks[nextTickToCross].secondsGrowthOutside;

        if (zeroForOne) {
            // Moving backwards through the linked list.
            // Liquidity cannot overflow due to the MAX_TICK_LIQUIDITY requirement.
            unchecked {
                if ((nextTickToCross / int24(tickSpacing)) % 2 == 0) {
                    currentLiquidity -= ticks[nextTickToCross].liquidity;
                } else {
                    currentLiquidity += ticks[nextTickToCross].liquidity;
                }
            }
            ticks[nextTickToCross].feeGrowthOutside0 = feeGrowthGlobalB - ticks[nextTickToCross].feeGrowthOutside0;
            ticks[nextTickToCross].feeGrowthOutside1 = feeGrowthGlobalA - ticks[nextTickToCross].feeGrowthOutside1;
            nextTickToCross = ticks[nextTickToCross].previousTick;
        } else {
            // Moving forwards through the linked list.
            unchecked {
                if ((nextTickToCross / int24(tickSpacing)) % 2 == 0) {
                    currentLiquidity += ticks[nextTickToCross].liquidity;
                } else {
                    currentLiquidity -= ticks[nextTickToCross].liquidity;
                }
            }
            ticks[nextTickToCross].feeGrowthOutside1 = feeGrowthGlobalB - ticks[nextTickToCross].feeGrowthOutside1;
            ticks[nextTickToCross].feeGrowthOutside0 = feeGrowthGlobalA - ticks[nextTickToCross].feeGrowthOutside0;
            nextTickToCross = ticks[nextTickToCross].nextTick;
        }
        return (currentLiquidity, nextTickToCross);
    }

    struct InsertCache {
        int24 tickAtPrice;
        uint128 currentLowerLiquidity;
        uint128 currentUpperLiquidity;
    }

    function insert(
        mapping(int24 => IConcentratedLiquidityPoolStruct.Tick) storage ticks,
        uint256 feeGrowthGlobal0,
        uint256 feeGrowthGlobal1,
        uint160 secondsGrowthGlobal,
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint128 amount,
        int24 nearestTick,
        uint160 currentPrice
    ) public returns (int24) {
        require(lower < upper, "WRONG_ORDER");
        require(TickMath.MIN_TICK <= lower, "LOWER_RANGE");
        require(upper <= TickMath.MAX_TICK, "UPPER_RANGE");

        /// @dev InsertCache is used to avoid stack too deep error
        InsertCache memory insertCache = InsertCache({
            tickAtPrice: TickMath.getTickAtSqrtRatio(currentPrice),
            currentLowerLiquidity: ticks[lower].liquidity,
            currentUpperLiquidity: ticks[upper].liquidity
        });

        {
            // Stack overflow.
            if (insertCache.currentLowerLiquidity != 0 || lower == TickMath.MIN_TICK) {
                // We are adding liquidity to an existing tick.
                ticks[lower].liquidity = insertCache.currentLowerLiquidity + amount;

                /// @dev newly initialised MIN_TICK; since it's a given that (insertParams.lower <= currentTick) == true check is not done
                if (lower == TickMath.MIN_TICK && insertCache.currentLowerLiquidity == 0) {
                    ticks[lower].feeGrowthOutside0 = feeGrowthGlobal0;
                    ticks[lower].feeGrowthOutside1 = feeGrowthGlobal1;
                    ticks[lower].secondsGrowthOutside = secondsGrowthGlobal;
                }
            } else {
                // We are inserting a new tick.
                IConcentratedLiquidityPoolStruct.Tick storage old = ticks[lowerOld];
                int24 oldNextTick = old.nextTick;

                require((old.liquidity != 0 || lowerOld == TickMath.MIN_TICK) && lowerOld < lower && lower < oldNextTick, "LOWER_ORDER");

                if (lower <= insertCache.tickAtPrice) {
                    ticks[lower] = IConcentratedLiquidityPoolStruct.Tick(
                        lowerOld,
                        oldNextTick,
                        amount,
                        feeGrowthGlobal0,
                        feeGrowthGlobal1,
                        secondsGrowthGlobal
                    );
                } else {
                    ticks[lower] = IConcentratedLiquidityPoolStruct.Tick(lowerOld, oldNextTick, amount, 0, 0, 0);
                }

                old.nextTick = lower;
                ticks[oldNextTick].previousTick = lower;
            }
        }

        if (insertCache.currentUpperLiquidity != 0 || upper == TickMath.MAX_TICK) {
            // We are adding liquidity to an existing tick.
            ticks[upper].liquidity = insertCache.currentUpperLiquidity + amount;

            /// @dev since it's a given that in the case of a newly initialised MAX_TICK (insertParams.upper <= currentTick) == false no need to update MAX_TICK's growth outside data; defaults of 0 is correct
        } else {
            // Inserting a new tick.
            IConcentratedLiquidityPoolStruct.Tick storage old = ticks[upperOld];
            int24 oldNextTick = old.nextTick;

            require(old.liquidity != 0 && oldNextTick > upper && upperOld < upper, "UPPER_ORDER");

            if (upper <= insertCache.tickAtPrice) {
                ticks[upper] = IConcentratedLiquidityPoolStruct.Tick(
                    upperOld,
                    oldNextTick,
                    amount,
                    feeGrowthGlobal0,
                    feeGrowthGlobal1,
                    secondsGrowthGlobal
                );
            } else {
                ticks[upper] = IConcentratedLiquidityPoolStruct.Tick(upperOld, oldNextTick, amount, 0, 0, 0);
            }
            old.nextTick = upper;
            ticks[oldNextTick].previousTick = upper;
        }

        if (nearestTick < upper && upper <= insertCache.tickAtPrice) {
            nearestTick = upper;
        } else if (nearestTick < lower && lower <= insertCache.tickAtPrice) {
            nearestTick = lower;
        }

        return nearestTick;
    }

    function remove(
        mapping(int24 => IConcentratedLiquidityPoolStruct.Tick) storage ticks,
        int24 lower,
        int24 upper,
        uint128 amount,
        int24 nearestTick
    ) public returns (int24) {
        IConcentratedLiquidityPoolStruct.Tick storage current = ticks[lower];

        if (lower != TickMath.MIN_TICK && current.liquidity == amount) {
            // Delete lower tick.
            IConcentratedLiquidityPoolStruct.Tick storage previous = ticks[current.previousTick];
            IConcentratedLiquidityPoolStruct.Tick storage next = ticks[current.nextTick];

            previous.nextTick = current.nextTick;
            next.previousTick = current.previousTick;

            if (nearestTick == lower) nearestTick = current.previousTick;

            delete ticks[lower];
        } else {
            unchecked {
                current.liquidity -= amount;
            }
        }

        current = ticks[upper];

        if (upper != TickMath.MAX_TICK && current.liquidity == amount) {
            // Delete upper tick.
            IConcentratedLiquidityPoolStruct.Tick storage previous = ticks[current.previousTick];
            IConcentratedLiquidityPoolStruct.Tick storage next = ticks[current.nextTick];

            previous.nextTick = current.nextTick;
            next.previousTick = current.previousTick;

            if (nearestTick == upper) nearestTick = current.previousTick;

            delete ticks[upper];
        } else {
            unchecked {
                current.liquidity -= amount;
            }
        }

        return nearestTick;
    }
}

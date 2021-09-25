// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "./TickMath.sol";

/// @notice Tick management library for ranged liquidity.
library Ticks {
    struct Tick {
        int24 previousTick;
        int24 nextTick;
        uint128 liquidity;
        uint256 feeGrowthOutside0; /// @dev Per unit of liquidity.
        uint256 feeGrowthOutside1;
        uint160 secondsPerLiquidityOutside;
    }

    function cross(
        mapping(int24 => Tick) storage ticks,
        int24 nextTickToCross,
        uint160 secondsPerLiquidity,
        uint256 currentLiquidity,
        uint256 feeGrowthGlobal,
        bool zeroForOne
    ) internal returns (uint256, int24) {
        ticks[nextTickToCross].secondsPerLiquidityOutside = secondsPerLiquidity - ticks[nextTickToCross].secondsPerLiquidityOutside;
        if (zeroForOne) {
            /// @dev Going left.
            if (nextTickToCross % 2 == 0) {
                currentLiquidity -= ticks[nextTickToCross].liquidity;
            } else {
                currentLiquidity += ticks[nextTickToCross].liquidity;
            }
            nextTickToCross = ticks[nextTickToCross].previousTick;
            ticks[nextTickToCross].feeGrowthOutside0 = feeGrowthGlobal - ticks[nextTickToCross].feeGrowthOutside0;
        } else {
            /// @dev Going right.
            if (nextTickToCross % 2 == 0) {
                currentLiquidity += ticks[nextTickToCross].liquidity;
            } else {
                currentLiquidity -= ticks[nextTickToCross].liquidity;
            }
            nextTickToCross = ticks[nextTickToCross].nextTick;
            ticks[nextTickToCross].feeGrowthOutside1 = feeGrowthGlobal - ticks[nextTickToCross].feeGrowthOutside1;
        }

        return (currentLiquidity, nextTickToCross);
    }

    function insert(
        mapping(int24 => Tick) storage ticks,
        int24 nearestTick,
        uint24 tickSpacing,
        uint256 feeGrowthGlobal0,
        uint256 feeGrowthGlobal1,
        uint160 secondsPerLiquidity,
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint128 amount,
        uint160 currentPrice
    ) internal returns (int24) {
        require(uint24(lower) % tickSpacing == 0, "LOWER_EVEN");
        require((uint24(lower) / tickSpacing) % 2 == 0, "LOWER_EVEN");

        require(uint24(upper) % tickSpacing == 1, "UPPER_ODD");
        require((uint24(upper) / tickSpacing) % 2 == 1, "UPPER_ODD");

        require(lower < upper, "WRONG_ORDER");

        require(TickMath.MIN_TICK <= lower && lower < TickMath.MAX_TICK, "LOWER_RANGE");
        require(TickMath.MIN_TICK < upper && upper <= TickMath.MAX_TICK, "UPPER_RANGE");

        int24 currentNearestTick = nearestTick;

        if (ticks[lower].liquidity != 0 || lower == TickMath.MIN_TICK) {
            /// @dev We are adding liquidity to an existing tick.
            ticks[lower].liquidity += amount;
        } else {
            /// @dev Inserting a new tick.
            Ticks.Tick storage old = ticks[lowerOld];

            require((old.liquidity != 0 || lowerOld == TickMath.MIN_TICK) && lowerOld < lower && lower < old.nextTick, "LOWER_ORDER");

            if (lower <= currentNearestTick) {
                ticks[lower] = Ticks.Tick(lowerOld, old.nextTick, amount, feeGrowthGlobal0, feeGrowthGlobal1, secondsPerLiquidity);
            } else {
                ticks[lower] = Ticks.Tick(lowerOld, old.nextTick, amount, 0, 0, 0);
            }

            old.nextTick = lower;
        }

        if (ticks[upper].liquidity != 0 || upper == TickMath.MAX_TICK) {
            /// @dev We are adding liquidity to an existing tick.
            ticks[upper].liquidity += amount;
        } else {
            /// @dev Inserting a new tick.
            Ticks.Tick storage old = ticks[upperOld];

            require(old.liquidity != 0 && old.nextTick > upper && upperOld < upper, "UPPER_ORDER");

            if (upper <= currentNearestTick) {
                ticks[upper] = Ticks.Tick(upperOld, old.nextTick, amount, feeGrowthGlobal0, feeGrowthGlobal1, secondsPerLiquidity);
            } else {
                ticks[upper] = Ticks.Tick(upperOld, old.nextTick, amount, 0, 0, 0);
            }

            old.nextTick = upper;
        }

        int24 actualNearestTick = TickMath.getTickAtSqrtRatio(currentPrice);

        if (currentNearestTick < lower && lower <= actualNearestTick) currentNearestTick = lower;

        if (currentNearestTick < upper && upper <= actualNearestTick) currentNearestTick = upper;

        return currentNearestTick;
    }

    function remove(
        mapping(int24 => Tick) storage ticks,
        int24 nearestTick,
        int24 lower,
        int24 upper,
        uint128 amount
    ) internal returns (int24) {
        Ticks.Tick storage current = ticks[lower];

        if (lower != TickMath.MIN_TICK && current.liquidity == amount) {
            /// @dev Delete lower tick.
            Ticks.Tick storage previous = ticks[current.previousTick];
            Ticks.Tick storage next = ticks[current.nextTick];

            previous.nextTick = current.nextTick;
            next.previousTick = current.previousTick;

            if (nearestTick == lower) nearestTick = current.previousTick;

            delete ticks[lower];
        } else {
            current.liquidity -= amount;
        }

        current = ticks[upper];

        if (upper != TickMath.MAX_TICK && current.liquidity == amount) {
            /// @dev Delete upper tick.
            Ticks.Tick storage previous = ticks[current.previousTick];
            Ticks.Tick storage next = ticks[current.nextTick];

            previous.nextTick = current.nextTick;
            next.previousTick = current.previousTick;

            if (nearestTick == upper) nearestTick = current.previousTick;

            delete ticks[upper];
        } else {
            current.liquidity -= amount;
        }

        return nearestTick;
    }
}

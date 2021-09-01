// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

library Ticks {
    struct Tick {
        int24 previousTick;
        int24 nextTick;
        uint128 liquidity;
        uint256 feeGrowthOutside0; // @dev Per unit of liquidity.
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
            // Going left.
            if (nextTickToCross % 2 == 0) {
                currentLiquidity -= ticks[nextTickToCross].liquidity;
            } else {
                currentLiquidity += ticks[nextTickToCross].liquidity;
            }
            nextTickToCross = ticks[nextTickToCross].previousTick;
            ticks[nextTickToCross].feeGrowthOutside0 = feeGrowthGlobal - ticks[nextTickToCross].feeGrowthOutside0;
        } else {
            // Going right.
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
}

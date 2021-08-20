// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;
pragma experimental ABIEncoderV2;

import "../../libraries/concentratedPool/TickMath.sol";

// todo import interface for this
interface IConcentratedLiquidityPool {
    struct Tick {
        int24 previousTick;
        int24 nextTick;
        uint128 liquidity;
        uint256 feeGrowthOutside0;
        uint256 feeGrowthOutside1;
    }

    function ticks(int24 _tick) external view returns (Tick memory tick);
}

contract ConcentratedLiquidityPoolHelper {
    struct SimpleTick {
        int24 index;
        uint128 liquidity;
    }

    function getTickState(IConcentratedLiquidityPool pool, uint24 tickCount) external view returns (SimpleTick[] memory) {
        SimpleTick[] memory ticks = new SimpleTick[](tickCount); // todo save tickCount in the core contract

        IConcentratedLiquidityPool.Tick memory tick;
        uint24 i = 0;
        int24 current = TickMath.MIN_TICK;

        while (current != TickMath.MAX_TICK) {
            tick = pool.ticks(current);
            ticks[i++] = SimpleTick({index: current, liquidity: tick.liquidity});
            current = tick.nextTick;
        }

        tick = pool.ticks(current);
        ticks[i] = SimpleTick({index: TickMath.MAX_TICK, liquidity: tick.liquidity});

        return ticks;
    }
}

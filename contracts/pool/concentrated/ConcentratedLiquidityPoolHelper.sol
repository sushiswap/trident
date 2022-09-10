// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IConcentratedLiquidityPool.sol";
import "../../libraries/TickMath.sol";
import "../../libraries/Ticks.sol";

/// @notice Trident Concentrated Liquidity Pool periphery contract to read state.
contract ConcentratedLiquidityPoolHelper {
    struct SimpleTick {
        int24 index;
        uint128 liquidity;
    }

    function getTickCount(IConcentratedLiquidityPool pool) public view returns (uint256 tickCount) {
        tickCount = 1;
        int24 current = TickMath.MIN_TICK;
        IConcentratedLiquidityPool.Tick memory tick;

        while (current != TickMath.MAX_TICK) {
            tick = pool.ticks(current);
            ++tickCount;
            current = tick.nextTick;
        }
    }

    function getTickState(IConcentratedLiquidityPool pool) external view returns (SimpleTick[] memory) {
        uint256 tickCount = getTickCount(pool);
        SimpleTick[] memory ticks = new SimpleTick[](tickCount);

        IConcentratedLiquidityPool.Tick memory tick;
        uint24 i;
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

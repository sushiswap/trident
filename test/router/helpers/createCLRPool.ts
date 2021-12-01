import { CLRPool, CLTick } from "@sushiswap/tines";
import { ConcentratedLiquidityPool } from "../../../types";

const priceBase = Math.pow(2, 96);
const feeBase = 1000_000;

export async function createCLRPool(pool: ConcentratedLiquidityPool): Promise<CLRPool> {
  const address = pool.address;
  const { _token0, _token1, _swapFee, _tickSpacing } = await pool.getImmutables();
  const token0 = {
    name: _token0,
    address: _token0,
  };
  const token1 = {
    name: _token1,
    address: _token1,
  };
  const [reserve0, reserve1] = await pool.getReserves();
  const [sqrtPrice, nearestTickIndex] = await pool.getPriceAndNearestTicks();
  const liquidity = parseInt((await pool.liquidity()).toString());

  const ticks: CLTick[] = [];
  let tickIndex = -887272;
  let nearestTick = -2;
  while (1) {
    if (tickIndex === nearestTickIndex) nearestTick = ticks.length;
    const tick = await pool.ticks(tickIndex);
    ticks.push({ index: tickIndex, DLiquidity: parseInt(tick.liquidity.toString()) });
    if (tickIndex === tick.nextTick) break;
    tickIndex = tick.nextTick;
  }

  return new CLRPool(
    address,
    token0,
    token1,
    _swapFee / feeBase,
    _tickSpacing,
    reserve0,
    reserve1,
    liquidity,
    parseInt(sqrtPrice.toString()) / priceBase,
    nearestTick,
    ticks
  );
}

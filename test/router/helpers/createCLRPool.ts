import { CLRPool, CLTick } from "@sushiswap/tines";
import { ConcentratedLiquidityPool, ConcentratedLiquidityPoolHelper } from "../../../types";
import { SimpleTickStructOutput } from "../../../types/ConcentratedLiquidityPoolHelper";

const priceBase = Math.pow(2, 96);
const feeBase = 1000_000;

export async function createCLRPool(pool: ConcentratedLiquidityPool): Promise<CLRPool> {
  const address = pool.address;
  const { _token0, _token1, _swapFee, _tickSpacing } = await pool.getImmutables();
  const token0 = {
    name: _token0,
    address: _token0,
    symbol: _token0,
  };
  const token1 = {
    name: _token1,
    address: _token1,
    symbol: _token1,
  };
  const [reserve0, reserve1] = await pool.getReserves();
  const [sqrtPrice, nearestTickIndex] = await pool.getPriceAndNearestTicks();
  const liquidity = await pool.liquidity();

  const ticks: CLTick[] = [];
  let tickIndex = -887272;
  let nearestTick = -2;
  while (1) {
    if (tickIndex === nearestTickIndex) nearestTick = ticks.length;
    const tick = await pool.ticks(tickIndex);
    ticks.push({ index: tickIndex, DLiquidity: tick.liquidity });
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
    sqrtPrice,
    nearestTick,
    ticks
  );
}

export async function createCLRPoolFast(
  pool: ConcentratedLiquidityPool,
  poolHelper: ConcentratedLiquidityPoolHelper
): Promise<CLRPool> {
  const address = pool.address;
  const { _token0, _token1, _swapFee, _tickSpacing } = await pool.getImmutables();
  const token0 = {
    name: _token0,
    address: _token0,
    symbol: _token0,
  };
  const token1 = {
    name: _token1,
    address: _token1,
    symbol: _token1,
  };
  const [reserve0, reserve1] = await pool.getReserves();
  const [sqrtPrice, nearestTickIndex] = await pool.getPriceAndNearestTicks();
  const liquidity = await pool.liquidity();

  const ticksData: SimpleTickStructOutput[] = await poolHelper.getTickState(pool.address);
  const ticks: CLTick[] = ticksData.map(({ index, liquidity }) => ({ index, DLiquidity: liquidity }));
  const nearestTick = ticks.findIndex((t) => t.index == nearestTickIndex);

  return new CLRPool(
    address,
    token0,
    token1,
    _swapFee / feeBase,
    _tickSpacing,
    reserve0,
    reserve1,
    liquidity,
    sqrtPrice,
    nearestTick,
    ticks
  );
}

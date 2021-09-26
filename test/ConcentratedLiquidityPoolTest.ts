import { ethers, network } from "hardhat";
import { addLiquidityViaRouter, getDx, getDy, getTickAtCurrentPrice, swapViaRouter } from "./harness/Concentrated";
import { getBigNumber } from "./harness/helpers";
import { Trident } from "./harness/Trident";

describe.only("Concentrated Liquidity Product Pool", function () {
  let snapshotId: string;
  let trident: Trident;

  before(async () => {
    trident = await Trident.Instance.init();
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshotId]);
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  describe("Mint and swap", async () => {
    it("Should mint liquidity (in / out of range, native / from bento, reusing ticks / new ticks)", async () => {
      for (const pool of trident.concentratedPools) {
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const step = 13860;
        // satisfy "lower even" & "upper odd" conditions
        const lower = tickAtPrice - step + (tickAtPrice % 2 == 0 ? 0 : 1);
        const upper = tickAtPrice + step + (tickAtPrice % 2 == 0 ? 1 : 0);
        const min = -887272;

        const addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(50),
          amount1Desired: getBigNumber(50),
          native: true,
          lowerOld: min,
          lower,
          upperOld: lower,
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };

        // normal mint
        await addLiquidityViaRouter(addLiquidityParams);

        // same range mint, from bento
        addLiquidityParams.native = !addLiquidityParams.native;
        await addLiquidityViaRouter(addLiquidityParams);

        // normal mint, narrower range
        addLiquidityParams.lowerOld = addLiquidityParams.lower;
        addLiquidityParams.lower = lower + step / 3;
        addLiquidityParams.upperOld = addLiquidityParams.lower;
        addLiquidityParams.upper = upper - step / 3;
        await addLiquidityViaRouter(addLiquidityParams);

        // mint on the same lower tick
        // @dev if a tick exists we dont' have to provide the tickOld param
        addLiquidityParams.lower = lower;
        addLiquidityParams.upperOld = upper;
        addLiquidityParams.upper = upper + step;
        await addLiquidityViaRouter(addLiquidityParams);

        // mint on the same upper tick
        addLiquidityParams.lower = lower - step;
        addLiquidityParams.lowerOld = min;
        addLiquidityParams.upper = upper;
        await addLiquidityViaRouter(addLiquidityParams);

        // mint below trading price
        addLiquidityParams.lower = lower;
        addLiquidityParams.upperOld = lower + step / 3;
        addLiquidityParams.upper = upper - 1.5 * step;
        await addLiquidityViaRouter(addLiquidityParams);

        // mint above trading price
        addLiquidityParams.lowerOld = upper - 1.5 * step;
        addLiquidityParams.lower = lower + 1.5 * step;
        addLiquidityParams.upper = upper;
        await addLiquidityViaRouter(addLiquidityParams);
      }
    });

    it("Should add liquidity and swap (without crossing)", async () => {
      for (const pool of trident.concentratedPools) {
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const step = 13860;
        const lower = tickAtPrice - step + (tickAtPrice % 2 == 0 ? 0 : 1);
        const upper = tickAtPrice + step + (tickAtPrice % 2 == 0 ? 1 : 0);
        const min = -887272;

        const addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(1000),
          amount1Desired: getBigNumber(1000),
          native: false,
          lowerOld: min,
          lower,
          upperOld: lower,
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };

        await addLiquidityViaRouter(addLiquidityParams);

        const lowerPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(lower);
        const currentPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(tickAtPrice);
        const maxDx = await getDx(await pool.liquidity(), lowerPrice, currentPrice, false);

        // swap back and forth
        const output = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: true,
          inAmount: maxDx,
          recipient: trident.accounts[0].address,
        });

        await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: false,
          inAmount: output,
          recipient: trident.accounts[0].address,
        });
      }
    });

    it("Should add liquidity and swap (with crossing through empty space)", async () => {
      for (const pool of trident.concentratedPools) {
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const step = 13860;
        const lower = tickAtPrice - step + (tickAtPrice % 2 == 0 ? 0 : 1);
        const upper = tickAtPrice + step + (tickAtPrice % 2 == 0 ? 1 : 0);
        const min = -887272;

        const addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(100),
          amount1Desired: getBigNumber(100),
          native: false,
          lowerOld: min,
          lower,
          upperOld: lower,
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };

        await addLiquidityViaRouter(addLiquidityParams);

        addLiquidityParams.amount0Desired = addLiquidityParams.amount0Desired.mul(2);
        addLiquidityParams.amount1Desired = addLiquidityParams.amount1Desired.mul(2);
        addLiquidityParams.lowerOld = upper;
        addLiquidityParams.lower = lower + 2.5 * step;
        addLiquidityParams.upperOld = addLiquidityParams.lower;
        addLiquidityParams.upper = upper + 2.5 * step;

        await addLiquidityViaRouter(addLiquidityParams);

        // swap accross a zero liquidity range and back
        //                       ▼ - - - - - - - - - -> ▼
        // ----|----|-------|xxxxxxxxxxxx|-------|xxxxxxxxxxx|-----

        const currentPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(tickAtPrice);
        const upperPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(upper);
        const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);

        const output = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: false,
          inAmount: maxDy.mul(2),
          recipient: trident.accounts[0].address,
        });

        await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: true,
          inAmount: output,
          recipient: trident.accounts[0].address,
        });
      }
    });
  });
});

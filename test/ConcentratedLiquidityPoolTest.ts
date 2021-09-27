import { ethers, network } from "hardhat";
import { addLiquidityViaRouter, getDx, getDy, getTickAtCurrentPrice, LinkedListHelper, swapViaRouter } from "./harness/Concentrated";
import { getBigNumber } from "./harness/helpers";
import { Trident } from "./harness/Trident";
import { expect } from "chai";

describe.only("Concentrated Liquidity Product Pool", function () {
  let snapshotId: string;
  let trident: Trident;
  const helper = new LinkedListHelper(-887272);
  const step = 10800;

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
        helper.reset();

        const tickSpacing = await pool.tickSpacing();
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
        const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

        // assume increasing tick value by one step brings us to a valid tick
        // satisfy "lower even" & "upper odd" conditions
        let lower = nearestEvenValidTick - step;
        let upper = nearestEvenValidTick + step + tickSpacing;

        let addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(50),
          amount1Desired: getBigNumber(50),
          native: true,
          lowerOld: helper.insert(lower),
          lower,
          upperOld: helper.insert(upper),
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
        addLiquidityParams = helper.setTicks(lower + step / 2, upper - step / 2, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        // mint on the same lower tick
        // @dev if a tick exists we dont' have to provide the tickOld param
        addLiquidityParams = helper.setTicks(lower, upper + step, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        // mint on the same upper tick
        addLiquidityParams = helper.setTicks(lower - step, upper, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        // mint below trading price
        addLiquidityParams = helper.setTicks(lower - 2 * step, upper - 2 * step, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        // mint above trading price
        addLiquidityParams = helper.setTicks(lower + 2 * step, upper + 2 * step, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);
      }
    });

    it("Should fail to mint with incorrect parameters for INVALID_TICK (LOWER), LOWER_EVEN, INVALID_TICK (UPPER), UPPER_ODD, WRONG_ORDER, LOWER_RANGE, UPPER_RANGE", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();
        const tickSpacing = await pool.tickSpacing();
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
        const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

        // INVALID_TICK (LOWER)
        let lower = nearestEvenValidTick - step + 1;
        let upper = nearestEvenValidTick + step + tickSpacing;
        let addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(50),
          amount1Desired: getBigNumber(50),
          native: true,
          lowerOld: helper.insert(lower),
          lower,
          upperOld: helper.insert(upper),
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };
        await expect(addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("INVALID_TICK");

        // LOWER_EVEN
        lower = nearestEvenValidTick - step + tickSpacing;
        upper = nearestEvenValidTick + step + tickSpacing;
        addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(50),
          amount1Desired: getBigNumber(50),
          native: true,
          lowerOld: helper.insert(lower),
          lower,
          upperOld: helper.insert(upper),
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };
        await expect(addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("LOWER_EVEN");

        // INVALID_TICK (UPPER)
        lower = nearestEvenValidTick - step;
        upper = nearestEvenValidTick + step + tickSpacing + 1;
        addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(50),
          amount1Desired: getBigNumber(50),
          native: true,
          lowerOld: helper.insert(lower),
          lower,
          upperOld: helper.insert(upper),
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };
        await expect(addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("INVALID_TICK");

        // UPPER_ODD
        lower = nearestEvenValidTick - step;
        upper = nearestEvenValidTick + step;
        addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(50),
          amount1Desired: getBigNumber(50),
          native: true,
          lowerOld: helper.insert(lower),
          lower,
          upperOld: helper.insert(upper),
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };
        await expect(addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("UPPER_ODD");

        // TODO: WRONG_ORDER, LOWER_RANGE, UPPER_RANGE
      }
    });

    it("Should add liquidity and swap (without crossing)", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();

        const tickSpacing = await pool.tickSpacing();
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
        const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

        // assume increasing tick value by one step brings us to a valid tick
        // satisfy "lower even" & "upper odd" conditions
        let lower = nearestEvenValidTick - step;
        let upper = nearestEvenValidTick + step + tickSpacing;

        let addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(1000),
          amount1Desired: getBigNumber(1000),
          native: false,
          lowerOld: helper.insert(lower),
          lower,
          upperOld: helper.insert(upper),
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

    it("Should add liquidity and swap (with crossing ticks)", async () => {
      for (const pool of [trident.concentratedPools[0]]) {
        helper.reset();

        const tickSpacing = await pool.tickSpacing();
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
        const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

        let lower = nearestEvenValidTick - step;
        let upper = nearestEvenValidTick + step + tickSpacing;

        let addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(100),
          amount1Desired: getBigNumber(100),
          native: false,
          lowerOld: helper.insert(lower),
          lower,
          upperOld: helper.insert(upper),
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };

        await addLiquidityViaRouter(addLiquidityParams);

        addLiquidityParams = helper.setTicks(lower + 3 * step, upper + 5 * step, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        addLiquidityParams = helper.setTicks(lower - 10 * step, upper + 10 * step, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        // swap accross the range and back
        //                       ▼ - - - - - - -> ▼
        // ----------------|xxxxxxxxxxx|-----|xxxxxxxxxx|--------
        // ----|xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|-----

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

    it("Should add liquidity and swap (with crossing through empty space)", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();

        const tickSpacing = await pool.tickSpacing();
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
        const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

        let lower = nearestEvenValidTick - step;
        let upper = nearestEvenValidTick + step + tickSpacing;

        let addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(100),
          amount1Desired: getBigNumber(100),
          native: false,
          lowerOld: helper.insert(lower),
          lower,
          upperOld: helper.insert(upper),
          upper,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };

        await addLiquidityViaRouter(addLiquidityParams);

        addLiquidityParams.amount0Desired = addLiquidityParams.amount0Desired.mul(2);
        addLiquidityParams.amount1Desired = addLiquidityParams.amount1Desired.mul(2);
        addLiquidityParams = helper.setTicks(lower + 3 * step, upper + 3 * step, addLiquidityParams);
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

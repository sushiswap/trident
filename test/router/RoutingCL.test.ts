import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
  addLiquidityViaManager,
  getDx,
  getDy,
  getTickAtCurrentPrice,
  LinkedListHelper,
  swapViaRouter,
} from "../harness/Concentrated";
import { getBigNumber } from "../utilities";
import { Trident } from "../harness/Trident";
import { createCLRPool } from "./helpers/createCLRPool";

let trident: Trident;
let defaultAddress: string;
const helper = new LinkedListHelper(-887272);
const step = 10800;
let snapshotId: string;

describe("Concentrated Pool Routing", async () => {
  before(async () => {
    trident = await Trident.Instance.init();
    defaultAddress = trident.accounts[0].address;
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshotId]);
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("swap without crossing", async () => {
    for (const pool of trident.concentratedPools) {
      helper.reset();

      const tickSpacing = (await pool.getImmutables())._tickSpacing;
      const tickAtPrice = await getTickAtCurrentPrice(pool);
      const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
      const nearestEvenValidTick =
        (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

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
        recipient: defaultAddress,
      };

      await addLiquidityViaManager(addLiquidityParams);

      const lowerPrice = await trident.tickMath.getSqrtRatioAtTick(lower);
      const currentPrice = (await pool.getPriceAndNearestTicks())._price;
      const maxDx = (await getDx(await pool.liquidity(), lowerPrice, currentPrice, false)).mul(9).div(10);

      const routePool = await createCLRPool(pool);
      const predictedOutput = routePool.calcOutByIn(parseInt(maxDx.toString()), true);

      const swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: true,
        inAmount: maxDx,
        recipient: defaultAddress,
      });

      const out = parseInt(swapTx.output.toString());
      // console.log("0 in", maxDx.toString(), 'out', out, "pred", predictedOutput[0],
      //   Math.abs(out/predictedOutput[0]-1));
      expect(Math.abs(out / predictedOutput.out - 1)).lessThan(1e-12);

      const routePool2 = await createCLRPool(pool);
      const predictedOutput2 = routePool2.calcOutByIn(parseInt(swapTx.output.toString()), false);

      const swapTx2 = await swapViaRouter({
        pool: pool,
        unwrapBento: false,
        zeroForOne: false,
        inAmount: swapTx.output,
        recipient: defaultAddress,
      });

      const out2 = parseInt(swapTx2.output.toString());
      // console.log("1 in", swapTx.output.toString(), 'out', out2, "pred", predictedOutput2[0],
      //   Math.abs(out2/predictedOutput2[0]-1));
      expect(Math.abs(out2 / predictedOutput2.out - 1)).lessThan(1e-12);
    }
  });

  it("swap with input exact at cross point", async () => {
    for (const pool of trident.concentratedPools) {
      helper.reset();

      const tickSpacing = (await pool.getImmutables())._tickSpacing;
      const tickAtPrice = await getTickAtCurrentPrice(pool);
      const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
      const nearestEvenValidTick =
        (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

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
        recipient: defaultAddress,
      };

      await addLiquidityViaManager(addLiquidityParams);

      const lowerPrice = await trident.tickMath.getSqrtRatioAtTick(lower);
      const currentPrice = (await pool.getPriceAndNearestTicks())._price;
      const maxDx = await getDx(await pool.liquidity(), lowerPrice, currentPrice, false);

      const routePool = await createCLRPool(pool);
      const predictedOutput = routePool.calcOutByIn(parseInt(maxDx.toString()), true);

      const swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: true,
        inAmount: maxDx,
        recipient: defaultAddress,
      });

      const out = parseInt(swapTx.output.toString());
      // console.log("0 in", maxDx.toString(), 'out', out, "pred", predictedOutput[0],
      //   Math.abs(out/predictedOutput[0]-1));
      expect(Math.abs(out / predictedOutput.out - 1)).lessThan(1e-12);

      const routePool2 = await createCLRPool(pool);
      const predictedOutput2 = routePool2.calcOutByIn(parseInt(swapTx.output.toString()), false);

      const swapTx2 = await swapViaRouter({
        pool: pool,
        unwrapBento: false,
        zeroForOne: false,
        inAmount: swapTx.output,
        recipient: defaultAddress,
      });

      const out2 = parseInt(swapTx2.output.toString());
      // console.log("1 in", swapTx.output.toString(), 'out', out2, "pred", predictedOutput2[0],
      //   Math.abs(out2/predictedOutput2[0]-1));
      expect(Math.abs(out2 / predictedOutput2.out - 1)).lessThan(1e-12);
    }
  });

  it("Should add liquidity and swap (with crossing ticks)", async () => {
    for (const pool of trident.concentratedPools) {
      helper.reset();

      const tickSpacing = (await pool.getImmutables())._tickSpacing;
      const tickAtPrice = await getTickAtCurrentPrice(pool);
      const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
      const nearestEvenValidTick =
        (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

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
        recipient: defaultAddress,
      };

      await addLiquidityViaManager(addLiquidityParams);

      addLiquidityParams = helper.setTicks(lower + 3 * step, upper + 5 * step, addLiquidityParams);
      await addLiquidityViaManager(addLiquidityParams);

      addLiquidityParams = helper.setTicks(lower - 10 * step, upper + 10 * step, addLiquidityParams);
      await addLiquidityViaManager(addLiquidityParams);

      // swap accross the range and back
      //                       ▼ - - - - - - -> ▼
      // ----------------|xxxxxxxxxxx|-----|xxxxxxxxxx|--------
      // ----|xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|-----

      const currentPrice = (await pool.getPriceAndNearestTicks())._price;
      const upperPrice = await trident.tickMath.getSqrtRatioAtTick(upper);
      const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false).mul(2);

      const routePool = await createCLRPool(pool);
      const predictedOutput = routePool.calcOutByIn(parseInt(maxDy.toString()), false);

      const swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: maxDy,
        recipient: defaultAddress,
      });

      const out = parseInt(swapTx.output.toString());
      // console.log("0 in", maxDy.toString(), 'out', out, "pred", predictedOutput[0],
      //   Math.abs(out/predictedOutput[0]-1));
      expect(Math.abs(out / predictedOutput.out - 1)).lessThan(1e-12);

      const routePool2 = await createCLRPool(pool);
      const predictedOutput2 = routePool2.calcOutByIn(out, true);

      const swapTx2 = await swapViaRouter({
        pool: pool,
        unwrapBento: false,
        zeroForOne: true,
        inAmount: swapTx.output,
        recipient: defaultAddress,
      });

      const out2 = parseInt(swapTx2.output.toString());
      // console.log("1 in", out, 'out', out2, "pred", predictedOutput2[0],
      //   Math.abs(out2/predictedOutput2[0]-1));
      expect(Math.abs(out2 / predictedOutput2.out - 1)).lessThan(1e-9);
    }
  });

  it("Swap with crossing through empty space", async () => {
    for (const pool of trident.concentratedPools) {
      helper.reset();

      const tickSpacing = (await pool.getImmutables())._tickSpacing;
      const tickAtPrice = await getTickAtCurrentPrice(pool);
      const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
      const nearestEvenValidTick =
        (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

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
        recipient: defaultAddress,
      };

      await addLiquidityViaManager(addLiquidityParams);

      addLiquidityParams.amount0Desired = addLiquidityParams.amount0Desired.mul(2);
      addLiquidityParams.amount1Desired = addLiquidityParams.amount1Desired.mul(2);
      addLiquidityParams = helper.setTicks(lower + 3 * step, upper + 3 * step, addLiquidityParams);
      await addLiquidityViaManager(addLiquidityParams);

      // swap accross a zero liquidity range and back
      //                       ▼ - - - - - - - - - -> ▼
      // ----|----|-------|xxxxxxxxxxxx|-------|xxxxxxxxxxx|-----

      const currentPrice = (await pool.getPriceAndNearestTicks())._price;
      const upperPrice = await trident.tickMath.getSqrtRatioAtTick(upper);
      const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false).mul(2);

      const routePool = await createCLRPool(pool);
      const predictedOutput = routePool.calcOutByIn(parseInt(maxDy.toString()), false);

      const swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: maxDy,
        recipient: defaultAddress,
      });

      const out = parseInt(swapTx.output.toString());
      // console.log("0 in", maxDy.toString(), 'out', out, "pred", predictedOutput[0],
      //   Math.abs(out/predictedOutput[0]-1));
      expect(Math.abs(out / predictedOutput.out - 1)).lessThan(1e-12);

      const routePool2 = await createCLRPool(pool);
      const predictedOutput2 = routePool2.calcOutByIn(out, true);

      const swapTx2 = await swapViaRouter({
        pool: pool,
        unwrapBento: false,
        zeroForOne: true,
        inAmount: swapTx.output,
        recipient: defaultAddress,
      });

      const out2 = parseInt(swapTx2.output.toString());
      // console.log("1 in", out, 'out', out2, "pred", predictedOutput2[0],
      //   Math.abs(out2/predictedOutput2[0]-1));
      expect(Math.abs(out2 / predictedOutput2.out - 1)).lessThan(1e-9);
    }
  });
});

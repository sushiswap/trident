import { expect } from "chai";
import { addLiquidityViaRouter, getDx, getTickAtCurrentPrice, LinkedListHelper, swapViaRouter } from "../harness/Concentrated";
import { getBigNumber } from "../harness/helpers";
import { Trident } from "../harness/Trident";
import { createCLRPool } from "./helpers/createCLRPool";

let trident: Trident;
let defaultAddress: string;
const helper = new LinkedListHelper(-887272);
const step = 10800;

describe("Concentrated Pool Routing", async () => {
  before(async () => {
    trident = await Trident.Instance.init();
    defaultAddress = trident.accounts[0].address;
  });

  it("swap without crossing", async () => {
    for (const pool of trident.concentratedPools) {
      helper.reset();

      const tickSpacing = (await pool.getImmutables())._tickSpacing;
      const tickAtPrice = await getTickAtCurrentPrice(pool);
      const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
      const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

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

      await addLiquidityViaRouter(addLiquidityParams);

      const lowerPrice = await trident.tickMath.getSqrtRatioAtTick(lower);
      const currentPrice = (await pool.getPriceAndNearestTicks())._price;
      const maxDx = (await getDx(await pool.liquidity(), lowerPrice, currentPrice, false)).div(2);

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
      expect(Math.abs(out / predictedOutput[0] - 1)).lessThan(1e-14);

      const routePool2 = await createCLRPool(pool);
      const predictedOutput2 = routePool2.calcOutByIn(parseInt(swapTx.output.toString()), false);

      const swapTx2 = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: swapTx.output,
        recipient: defaultAddress,
      });

      const out2 = parseInt(swapTx2.output.toString());
      // console.log("1 in", swapTx.output.toString(), 'out', out2, "pred", predictedOutput2[0],
      //   Math.abs(out2/predictedOutput2[0]-1));
      expect(Math.abs(out2 / predictedOutput2[0] - 1)).lessThan(1e-14);
    }
  });
});

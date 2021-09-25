import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { addLiquidityViaRouter, getTickAtCurrentPrice, swapViaRouter } from "./harness/Concentrated";
import { getBigNumber, randBetween, ZERO } from "./harness/helpers";
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
    it("Should add liquidity and mint NFTs", async () => {
      const tickAtPrice = await getTickAtCurrentPrice(trident.concentratedPool);
      let lower = tickAtPrice % 2 == 0 ? tickAtPrice - 10000 : tickAtPrice - 10001;
      let upper = tickAtPrice % 2 == 0 ? tickAtPrice + 10001 : tickAtPrice + 10000;
      let lowerOld = -887272;
      let upperOld = lower;

      const addLiquidityParams = {
        pool: trident.concentratedPool,
        amount0Desired: getBigNumber(1000),
        amount1Desired: getBigNumber(2000),
        native: false,
        lowerOld,
        lower,
        upperOld,
        upper,
        positionOwner: trident.concentratedPoolManager.address,
        recipient: trident.accounts[0].address,
      };

      await addLiquidityViaRouter(addLiquidityParams);

      addLiquidityParams.upperOld = upper;
      addLiquidityParams.lower -= 1000;
      addLiquidityParams.upper += 1000;
      addLiquidityParams.native = true;

      await addLiquidityViaRouter(addLiquidityParams);

      await swapViaRouter({
        pool: trident.concentratedPool,
        unwrapBento: true,
        zeroForOne: true,
        inAmount: getBigNumber(10),
        recipient: trident.accounts[0].address,
      });

      await swapViaRouter({
        pool: trident.concentratedPool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: getBigNumber(10),
        recipient: trident.accounts[0].address,
      });
    });
  });
});

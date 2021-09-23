import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { addLiquidityViaRouter, getTickAtCurrentPrice, initialize } from "./harness/Concentrated";
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

  describe("Add liquidity", () => {
    it("Should add liquidity", async () => {
      const tickAtPrice = await getTickAtCurrentPrice(trident.concentratedPool);
      let lower = tickAtPrice % 2 == 0 ? tickAtPrice - 10000 : tickAtPrice - 10001;
      let upper = tickAtPrice % 2 == 0 ? tickAtPrice + 10001 : tickAtPrice + 10000;
      let lowerOld = -887272;
      let upperOld = lower;

      await addLiquidityViaRouter(
        trident.concentratedPool,
        getBigNumber(1000),
        getBigNumber(2000),
        false,
        lowerOld,
        lower,
        upperOld,
        upper,
        trident.concentratedPoolManager.address,
        trident.accounts[0].address
      );

      upperOld = upper;
      lower -= 1000;
      upper += 1000;

      await addLiquidityViaRouter(
        trident.concentratedPool,
        getBigNumber(3000),
        getBigNumber(2000),
        true,
        lowerOld,
        lower,
        upperOld,
        upper,
        trident.concentratedPoolManager.address,
        trident.accounts[0].address
      );
    });
  });
});

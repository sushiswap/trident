import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { addLiquidityViaRouter, getTickAtCurrentPrice, initialize } from "./harness/Concentrated";
import { getBigNumber, randBetween, ZERO } from "./harness/helpers";
import { Trident } from "./harness/Trident";

describe.only("Concentrated Liquidity Product Pool", function () {
  let snapshotId: string;
  let trident: Trident;

  before(async function () {
    trident = await initialize();
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshotId]);
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  describe("Add liquidity", function () {
    it("Should add liquidity", async function () {
      const tickAtPrice = await getTickAtCurrentPrice(trident.concentratedPool);
      const lower = tickAtPrice % 2 == 0 ? tickAtPrice - 10000 : tickAtPrice - 10001;
      const upper = tickAtPrice % 2 == 0 ? tickAtPrice + 10001 : tickAtPrice + 10000;

      await addLiquidityViaRouter(
        trident.concentratedPool,
        getBigNumber(1000),
        getBigNumber(2000),
        true,
        -887272,
        lower,
        lower,
        upper,
        trident.accounts[0].address,
        trident.concentratedPoolManager.address
      );
    });
  });
});

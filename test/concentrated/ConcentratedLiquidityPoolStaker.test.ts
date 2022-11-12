import { expect } from "chai";
import { ethers, network } from "hardhat";
import { PANIC_CODES } from "@nomicfoundation/hardhat-chai-matchers/panic";

import {
  addLiquidityViaManager,
  _addLiquidityViaManager,
  getDy,
  getTickAtCurrentPrice,
  LinkedListHelper,
  swapViaRouter,
} from "../harness/Concentrated";
import { getBigNumber } from "../utilities";
import { Trident } from "../harness/Trident";

describe("Concentrated Liquidity Product Pool", function () {
  let _snapshotId: string;
  let snapshotId: string;
  let trident: Trident;
  let defaultAddress: string;
  const helper = new LinkedListHelper(-887272);
  const step = 10; // 2^5 * 3^2 * 5^2 (nicely divisible number)

  before(async () => {
    _snapshotId = await ethers.provider.send("evm_snapshot", []);
    trident = await Trident.Instance.init();
    defaultAddress = trident.accounts[0].address;
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshotId]);
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  after(async () => {
    await network.provider.send("evm_revert", [_snapshotId]);
    _snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  describe("Invalid actions", async () => {
    it("rewards exceeds unclaimedRewards", async () => {
      helper.reset();
      const pool = trident.concentratedPools[0];
      const tickSpacing = (await pool.getImmutables())._tickSpacing;
      const tickAtPrice = await getTickAtCurrentPrice(pool);

      const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
      const nearestEvenValidTick =
        (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;
      const lower = nearestEvenValidTick - step;
      const upper = nearestEvenValidTick + step + tickSpacing;

      let addLiquidityParams = {
        pool: pool,
        amount0Desired: getBigNumber(100),
        amount1Desired: getBigNumber(100),
        native: true,
        lowerOld: helper.insert(lower - step),
        lower: lower - step,
        upperOld: helper.insert(upper + step),
        upper: upper + step,
        positionOwner: trident.concentratedPoolManager.address,
        recipient: defaultAddress,
      };

      const mintA = await addLiquidityViaManager(addLiquidityParams);

      // 1 swap should happen before we start an incentive
      const currentPrice = (await pool.getPriceAndNearestTicks())._price;
      const upperPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(lower + 2 * step);
      const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);

      let swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: maxDy.div(100),
        recipient: defaultAddress,
      });

      const block1 = await ethers.provider.getBlock(swapTx.tx.blockNumber as number);

      const timeShift = 60 * 60 * 24; // wait for 1 day before creating incentive and subscribing

      await network.provider.send("evm_setNextBlockTimestamp", [block1.timestamp + timeShift]);

      const incentiveLength = 10000; // in seconds
      const incentiveAmount = getBigNumber(1_000_000);

      const endTime = block1.timestamp + 1 + incentiveLength + timeShift;

      await trident.concentratedPoolStaker.addIncentive(pool.address, {
        owner: defaultAddress,
        token: trident.extraToken.address,
        rewardsUnclaimed: incentiveAmount,
        secondsClaimed: 0,
        startTime: block1.timestamp + 1 + timeShift,
        endTime,
        expiry: block1.timestamp + 999999999 + timeShift,
      });

      let incentive = await trident.concentratedPoolStaker.incentives(pool.address, 0);
      await network.provider.send("evm_setNextBlockTimestamp", [block1.timestamp + 2 + timeShift]);

      expect(incentive.secondsClaimed.toString()).to.be.eq("0", "didn't reset seconds claimed");
      await trident.concentratedPoolStaker.subscribe(mintA.tokenId, [0]);
      await network.provider.send("evm_setNextBlockTimestamp", [endTime - 10]);

      swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: maxDy.div(100),
        recipient: defaultAddress,
      });

      const rewardInfo = await trident.concentratedPoolStaker.getReward(mintA.tokenId, 0);

      expect(rewardInfo.rewards).to.be.greaterThan(incentiveAmount);

      const accuracy = 1_000_000_000;
      const ratio = rewardInfo.rewards.mul(accuracy).div(incentiveAmount);

      console.log("ratio(rewards/unclaimedRewards):", ratio.toNumber() / accuracy);

      const recipientA = trident.accounts[1].address;

      await expect(
        trident.concentratedPoolStaker.claimRewards(mintA.tokenId, [0], recipientA, false)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW);
    });
  });
});

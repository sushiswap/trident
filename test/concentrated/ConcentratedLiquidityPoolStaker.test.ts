import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
  addLiquidityViaManager,
  _addLiquidityViaManager,
  removeLiquidityViaManager,
  collectFees,
  collectProtocolFee,
  getDx,
  getDy,
  getTickAtCurrentPrice,
  LinkedListHelper,
  swapViaRouter,
  TWO_POW_128,
} from "../harness/Concentrated";
import { getBigNumber, customError } from "../utilities";
import { Trident } from "../harness/Trident";

describe("Concentrated Liquidity Product Pool", function () {
  let _snapshotId: string;
  let snapshotId: string;
  let trident: Trident;
  let defaultAddress: string;
  const helper = new LinkedListHelper(-887272);
  const step = 10800; // 2^5 * 3^2 * 5^2 (nicely divisible number)

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

  describe("Valid actions", async () => {
    it("Should create incentive", async () => {
      helper.reset();
      const pool = trident.concentratedPools[0];
      const tickSpacing = (await pool.getImmutables())._tickSpacing;
      const tickAtPrice = await getTickAtCurrentPrice(pool);
      const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
      const nearestEvenValidTick =
        (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;
      const lower = nearestEvenValidTick - step;
      const upper = nearestEvenValidTick + step + tickSpacing;

      // add the following global liquidity
      //                  ▼
      // ---------------------|xxxxxxxxxxx|-----
      // --------|xxxxxxxxxxxxxxxxxxxxxxxx|----------
      // --------|xxxxxxxxxxxxxxxxxxxxxxxx|----------

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

      addLiquidityParams.amount0Desired = getBigNumber(200);
      addLiquidityParams.amount1Desired = getBigNumber(200);
      const mintB = await addLiquidityViaManager(addLiquidityParams);

      addLiquidityParams.amount0Desired = getBigNumber(100);
      addLiquidityParams.amount1Desired = getBigNumber(100);
      addLiquidityParams = helper.setTicks(lower + 2 * step, upper + 4 * step, addLiquidityParams);
      const mintC = await addLiquidityViaManager(addLiquidityParams);

      // 1 swap should happen before we start an incentive
      const currentPrice = (await pool.getPriceAndNearestTicks())._price;
      const upperPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(lower + 2 * step);
      const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);
      let swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: maxDy.div(3),
        recipient: defaultAddress,
      });

      const block = await ethers.provider.getBlock(swapTx.tx.blockNumber as number);
      const incentiveLength = 10000; // in seconds
      const incentiveAmount = getBigNumber(1000);

      await trident.concentratedPoolStaker.addIncentive(pool.address, {
        owner: defaultAddress,
        token: trident.extraToken.address,
        rewardsUnclaimed: incentiveAmount,
        secondsClaimed: 123,
        startTime: block.timestamp + 1,
        endTime: block.timestamp + 1 + incentiveLength,
        expiry: block.timestamp + 999999999,
      });
      let incentive = await trident.concentratedPoolStaker.incentives(pool.address, 0);
      await network.provider.send("evm_setNextBlockTimestamp", [block.timestamp + 2]);
      expect(incentive.secondsClaimed.toString()).to.be.eq("0", "didn't reset seconds claimed");
      await trident.concentratedPoolStaker.subscribe(mintA.tokenId, [0]);
      await trident.concentratedPoolStaker.subscribe(mintB.tokenId, [0]);
      await trident.concentratedPoolStaker.subscribe(mintC.tokenId, [0]);
      await network.provider.send("evm_setNextBlockTimestamp", [block.timestamp + incentiveLength / 4]);
      swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: maxDy.div(3),
        recipient: defaultAddress,
      });
      const recipientA = trident.accounts[1].address;
      const recipientB = trident.accounts[2].address;
      const recipientC = trident.accounts[3].address;
      await trident.concentratedPoolStaker.claimRewards(mintA.tokenId, [0], recipientA, false);
      await trident.concentratedPoolStaker.claimRewards(mintB.tokenId, [0], recipientB, false);
      incentive = await trident.concentratedPoolStaker.incentives(pool.address, 0);
      const secondsClaimed = incentive.secondsClaimed.div(TWO_POW_128);
      const rewardsUnclaimed = incentive.rewardsUnclaimed;
      const expectedRewardsUnclaimed = incentiveAmount.div(4).mul(3); // tree quarters
      const rewardsA = await trident.bento.balanceOf(trident.extraToken.address, recipientA);
      const rewardsB = await trident.bento.balanceOf(trident.extraToken.address, recipientB);
      expect(secondsClaimed.sub(1).lte(incentiveLength / 4) && secondsClaimed.add(1).gte(incentiveLength / 4)).to.be.eq(
        true,
        "didn't claim a querter of reward duration"
      );
      expect(
        rewardsUnclaimed.sub(10).lte(expectedRewardsUnclaimed) && rewardsUnclaimed.add(10).gte(expectedRewardsUnclaimed)
      ).to.be.eq(true, "didn't claim a quarter of rewards");
      let ratio = rewardsA.mul(2).mul(1e6).div(rewardsB);
      expect(ratio.gte(999900) && ratio.lte(1000100)).to.be.eq(true, "Didn't split rewards proportionally");
      const newCurrentPrice = (await pool.getPriceAndNearestTicks())._price;
      const oldLiq = await pool.liquidity();
      const newMaxDy = await getDy(await pool.liquidity(), newCurrentPrice, upperPrice, false);
      swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: newMaxDy.mul(2),
        recipient: defaultAddress,
      });
      const newLiq = await pool.liquidity();
      expect(newLiq.gt(oldLiq), "we didn't move into another range");
      await network.provider.send("evm_setNextBlockTimestamp", [block.timestamp + incentiveLength + 1000]);
      swapTx = await swapViaRouter({
        pool: pool,
        unwrapBento: true,
        zeroForOne: false,
        inAmount: newMaxDy.div(10),
        recipient: defaultAddress,
      });
      await trident.concentratedPoolStaker.claimRewards(mintA.tokenId, [0], recipientA, false);
      await trident.concentratedPoolStaker.claimRewards(mintB.tokenId, [0], recipientB, false);
      await trident.concentratedPoolStaker.claimRewards(mintC.tokenId, [0], recipientC, false);
      const newRewardsA = await trident.bento.balanceOf(trident.extraToken.address, recipientA);
      const newRewardsB = await trident.bento.balanceOf(trident.extraToken.address, recipientB);
      const newRewardsC = await trident.bento.balanceOf(trident.extraToken.address, recipientC);
      ratio = rewardsA.mul(2).mul(1e6).div(rewardsB);
      expect(ratio.gte(999900) && ratio.lte(1000100)).to.be.eq(true, "Didn't split rewards proportionally");
      incentive = await trident.concentratedPoolStaker.incentives(pool.address, 0);
      const sum = newRewardsA.add(newRewardsB).add(newRewardsC);
      expect(sum.add(incentive.rewardsUnclaimed)).to.be.eq(
        incentiveAmount.toString(),
        "We distributed the wrong amount of tokens"
      );
      expect(incentive.rewardsUnclaimed.lt("99999"), "didn't leave dust in incentive");
    });
  });
});

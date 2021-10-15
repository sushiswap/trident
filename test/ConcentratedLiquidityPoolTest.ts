import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
  addLiquidityViaRouter,
  _addLiquidityViaRouter,
  removeLiquidityViaManager,
  collectFees,
  collectProtocolFee,
  getDx,
  getDy,
  getTickAtCurrentPrice,
  LinkedListHelper,
  swapViaRouter,
  TWO_POW_128,
} from "./harness/Concentrated";
import { getBigNumber } from "./harness/helpers";
import { Trident, TWO_POW_96 } from "./harness/Trident";

describe("Concentrated Liquidity Product Pool", function () {
  let snapshotId: string;
  let trident: Trident;
  let defaultAddress: string;
  const helper = new LinkedListHelper(-887272);
  const step = 10800;

  before(async () => {
    trident = await Trident.Instance.init();
    defaultAddress = trident.accounts[0].address;
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshotId]);
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  describe("Valid actions", async () => {
    it("Should mint liquidity (in / out of range, native / from bento, reusing ticks / new ticks)", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();

        const tickSpacing = (await pool.getImmutables())._tickSpacing;
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
          recipient: defaultAddress,
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

    it("Should add liquidity and swap (without crossing)", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();

        const tickSpacing = (await pool.getImmutables())._tickSpacing;
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
          recipient: defaultAddress,
        };

        await addLiquidityViaRouter(addLiquidityParams);

        const lowerPrice = await trident.tickMath.getSqrtRatioAtTick(lower);
        const currentPrice = (await pool.getPriceAndNearestTicks())._price;
        const maxDx = await getDx(await pool.liquidity(), lowerPrice, currentPrice, false);

        // swap back and forth
        const swapTx = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: true,
          inAmount: maxDx,
          recipient: defaultAddress,
        });

        await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: false,
          inAmount: swapTx.output,
          recipient: defaultAddress,
        });
      }
    });

    it("Should add liquidity and swap (with crossing ticks)", async () => {
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

        await addLiquidityViaRouter(addLiquidityParams);

        addLiquidityParams = helper.setTicks(lower + 3 * step, upper + 5 * step, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        addLiquidityParams = helper.setTicks(lower - 10 * step, upper + 10 * step, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        // swap accross the range and back
        //                       ▼ - - - - - - -> ▼
        // ----------------|xxxxxxxxxxx|-----|xxxxxxxxxx|--------
        // ----|xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|-----

        const currentPrice = (await pool.getPriceAndNearestTicks())._price;
        const upperPrice = await trident.tickMath.getSqrtRatioAtTick(upper);
        const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);

        const swapTx = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: false,
          inAmount: maxDy.mul(2),
          recipient: defaultAddress,
        });

        await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: true,
          inAmount: swapTx.output,
          recipient: defaultAddress,
        });
      }
    });

    it("Should add liquidity and swap (with crossing through empty space)", async () => {
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

        await addLiquidityViaRouter(addLiquidityParams);

        addLiquidityParams.amount0Desired = addLiquidityParams.amount0Desired.mul(2);
        addLiquidityParams.amount1Desired = addLiquidityParams.amount1Desired.mul(2);
        addLiquidityParams = helper.setTicks(lower + 3 * step, upper + 3 * step, addLiquidityParams);
        await addLiquidityViaRouter(addLiquidityParams);

        // swap accross a zero liquidity range and back
        //                       ▼ - - - - - - - - - -> ▼
        // ----|----|-------|xxxxxxxxxxxx|-------|xxxxxxxxxxx|-----

        const currentPrice = (await pool.getPriceAndNearestTicks())._price;
        const upperPrice = await trident.tickMath.getSqrtRatioAtTick(upper);
        const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);

        const swapTx = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: false,
          inAmount: maxDy.mul(2),
          recipient: defaultAddress,
        });

        await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: true,
          inAmount: swapTx.output,
          recipient: defaultAddress,
        });
      }
    });

    it("Should distribute fees correctly", async () => {
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

        const tokenIdA = (await addLiquidityViaRouter(addLiquidityParams)).tokenId;

        addLiquidityParams.amount0Desired = addLiquidityParams.amount0Desired.mul(2);
        addLiquidityParams.amount1Desired = addLiquidityParams.amount1Desired.mul(2);
        const tokenIdB = (await addLiquidityViaRouter(addLiquidityParams)).tokenId;

        addLiquidityParams = helper.setTicks(lower - step * 2, upper - step * 2, addLiquidityParams);
        const tokenIdC = (await addLiquidityViaRouter(addLiquidityParams)).tokenId;

        // swap within tick
        const currentPrice = (await pool.getPriceAndNearestTicks())._price;
        const upperPrice = await trident.tickMath.getSqrtRatioAtTick(upper);
        const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);

        let swapTx = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: false,
          inAmount: maxDy,
          recipient: defaultAddress,
        });

        swapTx = await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: true,
          inAmount: swapTx.output,
          recipient: defaultAddress,
        });

        const positionNewFeeGrowth = await pool.rangeFeeGrowth(lower, upper);
        const globalFeeGrowth0 = await pool.feeGrowthGlobal0();
        const globalFeeGrowth1 = await pool.feeGrowthGlobal1();
        expect(positionNewFeeGrowth.feeGrowthInside0.toString()).to.be.eq(
          globalFeeGrowth0.toString(),
          "Fee growth 0 wasn't accredited to the positions"
        );
        expect(positionNewFeeGrowth.feeGrowthInside1.toString()).to.be.eq(
          globalFeeGrowth1.toString(),
          "Fee growth 1 wasn't accredited to the positions"
        );
        const smallerPositionFees1 = await collectFees({ pool, tokenId: tokenIdA, recipient: defaultAddress, unwrapBento: false });

        swapTx = await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: false,
          inAmount: swapTx.output,
          recipient: defaultAddress,
        });

        await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: true,
          inAmount: swapTx.output,
          recipient: defaultAddress,
        });

        const smallerPositionFees2 = await collectFees({ pool, tokenId: tokenIdA, recipient: defaultAddress, unwrapBento: false });

        const smallerPositionFeesDy = smallerPositionFees2.dy.add(smallerPositionFees1.dy);
        const smallerPositionFeesDx = smallerPositionFees2.dx.add(smallerPositionFees1.dx);
        const biggerPositionFees = await collectFees({ pool, tokenId: tokenIdB, recipient: defaultAddress, unwrapBento: false });
        const outsidePositionFees = await collectFees({ pool, tokenId: tokenIdC, recipient: defaultAddress, unwrapBento: false });
        const ratioY = smallerPositionFeesDy.mul(1e6).div(biggerPositionFees.dy.div(2));
        const ratioX = smallerPositionFeesDx.mul(1e6).div(biggerPositionFees.dx.div(2));
        // allow for small rounding errors that happen when users claim on different intervals
        expect(ratioY.lt(1000100) && ratioY.lt(999900), "fees 1 weren't proportionally split");
        expect(ratioX.lt(1000100) && ratioX.lt(999900), "fees 0 weren't proportionally split");
        expect(outsidePositionFees.dy.toString()).to.be.eq("0", "fees were acredited to a position not in range");
      }
    });

    it("Should collect protocolFee", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();

        const immutables = await pool.getImmutables();
        const tickSpacing = immutables._tickSpacing;
        const token0 = immutables._token0;
        const token1 = immutables._token1;
        const barFeeTo = immutables._barFeeTo;
        const oldBarFeeToBalanceToken0 = await trident.bento.balanceOf(token0, barFeeTo);
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
        const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;
        const oldBarFeeToBalanceToken1 = await trident.bento.balanceOf(token1, barFeeTo);

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
          recipient: defaultAddress,
        };

        await addLiquidityViaRouter(addLiquidityParams);

        const lowerPrice = await trident.tickMath.getSqrtRatioAtTick(lower);
        const currentPrice = (await pool.getPriceAndNearestTicks())._price;
        const maxDx = await getDx(await pool.liquidity(), lowerPrice, currentPrice, false);

        // swap back and forth
        const swapTx = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: true,
          inAmount: maxDx,
          recipient: defaultAddress,
        });

        await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: false,
          inAmount: swapTx.output,
          recipient: defaultAddress,
        });

        const { token0ProtocolFee, token1ProtocolFee } = await collectProtocolFee({ pool: pool });
        const barFeeToBalanceToken0 = await trident.bento.balanceOf(token0, barFeeTo);
        const barFeeToBalanceToken1 = await trident.bento.balanceOf(token1, barFeeTo);

        expect(barFeeToBalanceToken0.toString()).to.be.eq(
          oldBarFeeToBalanceToken0.add(token0ProtocolFee),
          "didn't send the correct amount of token0 protocol fee to bar fee to"
        );
        expect(barFeeToBalanceToken1.toString()).to.be.eq(
          oldBarFeeToBalanceToken1.add(token1ProtocolFee),
          "didn't send the correct amount of token0 protocol fee to bar fee to"
        );
      }
    });

    it("Should burn the position and receive tokens back", async () => {
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

        const mint = await addLiquidityViaRouter(addLiquidityParams);
        const userLiquidity = (await trident.concentratedPoolManager.positions(mint.tokenId)).liquidity;
        const userLiquidityPartial = userLiquidity.sub(userLiquidity.div(3));

        let removeLiquidityParams = {
          pool: pool,
          tokenId: Number(mint.tokenId.toString()),
          liquidityAmount: userLiquidityPartial,
          recipient: trident.accounts[0].address,
          unwrapBento: true,
        };
        await removeLiquidityViaManager(removeLiquidityParams);
        removeLiquidityParams.liquidityAmount = userLiquidity.sub(userLiquidityPartial);
        await removeLiquidityViaManager(removeLiquidityParams);
      }
    });

    it("Should calcualte seconds inside correctly", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();

        const tickSpacing = (await pool.getImmutables())._tickSpacing;
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
        const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

        let lowerA = nearestEvenValidTick - 10 * step;
        let upperA = nearestEvenValidTick + 10 * step + tickSpacing;
        let lowerB = nearestEvenValidTick + 3 * step;
        let upperB = nearestEvenValidTick + 9 * step + tickSpacing;
        let lowerC = nearestEvenValidTick + 6 * step;
        let upperC = nearestEvenValidTick + 9 * step + tickSpacing;

        let addLiquidityParams = {
          pool: pool,
          amount0Desired: getBigNumber(100),
          amount1Desired: getBigNumber(100),
          native: false,
          lowerOld: helper.insert(lowerA),
          lower: lowerA,
          upperOld: helper.insert(upperA),
          upper: upperA,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: defaultAddress,
        };
        const mintA = await addLiquidityViaRouter(addLiquidityParams);
        addLiquidityParams = helper.setTicks(lowerB, upperB, addLiquidityParams);
        const mintB = await addLiquidityViaRouter(addLiquidityParams);
        addLiquidityParams = helper.setTicks(lowerC, upperC, addLiquidityParams);
        const mintC = await addLiquidityViaRouter(addLiquidityParams);
        const liquidityA = mintA.liquidity;
        const liquidityB = mintB.liquidity;
        const liquidityC = mintC.liquidity;

        // execute each swap after some time
        //                  ▼ - - -> ▼ - - -> ▼ - - - -> ▼ - - -
        // --------------------------------------|xxxxxxxxxxxxxxxx|-----
        // --------------|----------------|xxxxxxxxxxxxxxxxxxxxxxx|-----
        // --------------|xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|-----

        const currentPrice = (await pool.getPriceAndNearestTicks())._price;
        const upperPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(lowerB);
        const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);
        let output = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: false,
          inAmount: maxDy.div(3).mul(2),
          recipient: defaultAddress,
        });
        const fistSplData = await pool.getSecondsGrowthAndLastObservation();
        let firstSplA = await trident.concentratedPoolManager.rangeSecondsInside(pool.address, lowerA, upperA);
        expect((await fistSplData)._secondsGrowthGlobal.toString()).to.be.eq(
          firstSplA.toString(),
          "didn't credit seconds per liquidity to active position"
        );
        await network.provider.send("evm_setNextBlockTimestamp", [fistSplData._lastObservation + 10000]);
        output = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: false,
          inAmount: maxDy.div(3).mul(2),
          recipient: defaultAddress,
        });
        const secondSplData = await pool.getSecondsGrowthAndLastObservation();
        const secondSplA = await trident.concentratedPoolManager.rangeSecondsInside(pool.address, lowerA, upperA);
        const secondSplB = await trident.concentratedPoolManager.rangeSecondsInside(pool.address, lowerB, upperB);
        expect(secondSplData._secondsGrowthGlobal.toString()).to.be.eq(
          secondSplA.toString(),
          "didn't credit seconds per liquidity to active position"
        );
        expect(secondSplB.eq(0)).to.be.true;
        const timeIncrease = 10000;
        await network.provider.send("evm_setNextBlockTimestamp", [secondSplData._lastObservation + timeIncrease]);
        output = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: false,
          inAmount: maxDy,
          recipient: defaultAddress,
        });
        const thirdSplA = await trident.concentratedPoolManager.rangeSecondsInside(pool.address, lowerA, upperA);
        const thirdSplB = await trident.concentratedPoolManager.rangeSecondsInside(pool.address, lowerB, upperB);
        const splAseconds = thirdSplA.sub(secondSplA).mul(liquidityA);
        const splBseconds = thirdSplB.sub(secondSplB).mul(liquidityB);
        const totalSeconds = splAseconds.add(splBseconds).div(TWO_POW_128);
        expect(totalSeconds.lte(timeIncrease) && totalSeconds.gte(timeIncrease - 3)).to.be.true;
      }
    });

    it("Should create incentive", async () => {
      helper.reset();
      const pool = trident.concentratedPools[0];
      const tickSpacing = (await pool.getImmutables())._tickSpacing;
      const tickAtPrice = await getTickAtCurrentPrice(pool);
      const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
      const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;
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
      const mintA = await addLiquidityViaRouter(addLiquidityParams);

      addLiquidityParams.amount0Desired = getBigNumber(200);
      addLiquidityParams.amount1Desired = getBigNumber(200);
      const mintB = await addLiquidityViaRouter(addLiquidityParams);

      addLiquidityParams.amount0Desired = getBigNumber(100);
      addLiquidityParams.amount1Desired = getBigNumber(100);
      addLiquidityParams = helper.setTicks(lower + 2 * step, upper + 4 * step, addLiquidityParams);
      const mintC = await addLiquidityViaRouter(addLiquidityParams);

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

      await trident.concentratedPoolManager.addIncentive(pool.address, {
        owner: defaultAddress,
        token: trident.extraToken.address,
        rewardsUnclaimed: incentiveAmount,
        secondsClaimed: 123,
        startTime: block.timestamp + 1,
        endTime: block.timestamp + 1 + incentiveLength,
        expiry: block.timestamp + 999999999,
      });
      let incentive = await trident.concentratedPoolManager.incentives(pool.address, 0);
      await network.provider.send("evm_setNextBlockTimestamp", [block.timestamp + 2]);
      expect(incentive.secondsClaimed.toString()).to.be.eq("0", "didn't reset seconds claimed");
      await trident.concentratedPoolManager.subscribe(mintA.tokenId, [0]);
      await trident.concentratedPoolManager.subscribe(mintB.tokenId, [0]);
      await trident.concentratedPoolManager.subscribe(mintC.tokenId, [0]);
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
      await trident.concentratedPoolManager.claimRewards(mintA.tokenId, [0], recipientA, false);
      await trident.concentratedPoolManager.claimRewards(mintB.tokenId, [0], recipientB, false);
      incentive = await trident.concentratedPoolManager.incentives(pool.address, 0);
      const secondsClaimed = incentive.secondsClaimed.div(TWO_POW_128);
      const rewardsUnclaimed = incentive.rewardsUnclaimed;
      const expectedRewardsUnclaimed = incentiveAmount.div(4).mul(3); // tree quarters
      const rewardsA = await trident.bento.balanceOf(trident.extraToken.address, recipientA);
      const rewardsB = await trident.bento.balanceOf(trident.extraToken.address, recipientB);
      expect(secondsClaimed.sub(1).lte(incentiveLength / 4) && secondsClaimed.add(1).gte(incentiveLength / 4)).to.be.eq(
        true,
        "didn't claim a querter of reward duration"
      );
      expect(rewardsUnclaimed.sub(10).lte(expectedRewardsUnclaimed) && rewardsUnclaimed.add(10).gte(expectedRewardsUnclaimed)).to.be.eq(
        true,
        "didn't claim a quarter of rewards"
      );
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
      await trident.concentratedPoolManager.claimRewards(mintA.tokenId, [0], recipientA, false);
      await trident.concentratedPoolManager.claimRewards(mintB.tokenId, [0], recipientB, false);
      await trident.concentratedPoolManager.claimRewards(mintC.tokenId, [0], recipientC, false);
      const newRewardsA = await trident.bento.balanceOf(trident.extraToken.address, recipientA);
      const newRewardsB = await trident.bento.balanceOf(trident.extraToken.address, recipientB);
      const newRewardsC = await trident.bento.balanceOf(trident.extraToken.address, recipientC);
      ratio = rewardsA.mul(2).mul(1e6).div(rewardsB);
      expect(ratio.gte(999900) && ratio.lte(1000100)).to.be.eq(true, "Didn't split rewards proportionally");
      incentive = await trident.concentratedPoolManager.incentives(pool.address, 0);
      const sum = newRewardsA.add(newRewardsB).add(newRewardsC);
      expect(sum.add(incentive.rewardsUnclaimed)).to.be.eq(incentiveAmount.toString(), "We distributed the wrong amount of tokens");
      expect(incentive.rewardsUnclaimed.lt("99999"), "didn't leave dust in incentive");
    });
  });

  describe("Invalid actions", async () => {
    it("Should fail to mint with incorrect parameters for INVALID_TICK (LOWER), LOWER_EVEN, INVALID_TICK (UPPER), UPPER_ODD, WRONG_ORDER, LOWER_RANGE, UPPER_RANGE", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();
        const tickSpacing = (await pool.getImmutables())._tickSpacing;
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
          lower: nearestEvenValidTick - step + 1,
          upperOld: helper.insert(upper),
          upper: nearestEvenValidTick + step + tickSpacing,
          positionOwner: trident.concentratedPoolManager.address,
          recipient: trident.accounts[0].address,
        };

        await expect(addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("INVALID_TICK");
        // LOWER_EVEN
        addLiquidityParams.lower = nearestEvenValidTick - step + tickSpacing;
        addLiquidityParams.upper = nearestEvenValidTick + step + tickSpacing;
        addLiquidityParams.lowerOld = helper.insert(addLiquidityParams.lower);
        addLiquidityParams.upperOld = helper.insert(addLiquidityParams.upper);
        await expect(addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("LOWER_EVEN");

        // INVALID_TICK (UPPER)
        addLiquidityParams.lower = nearestEvenValidTick - step;
        addLiquidityParams.upper = nearestEvenValidTick + step + tickSpacing + 1;
        addLiquidityParams.lowerOld = helper.insert(addLiquidityParams.lower);
        addLiquidityParams.upperOld = helper.insert(addLiquidityParams.upper);
        await expect(addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("INVALID_TICK");

        // UPPER_ODD
        addLiquidityParams.lower = nearestEvenValidTick - step;
        addLiquidityParams.upper = nearestEvenValidTick + step;
        addLiquidityParams.lowerOld = helper.insert(addLiquidityParams.lower);
        addLiquidityParams.upperOld = helper.insert(addLiquidityParams.upper);
        await expect(addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("UPPER_ODD");

        // WRONG ORDER
        addLiquidityParams.lower = nearestEvenValidTick + 3 * step;
        addLiquidityParams.upper = nearestEvenValidTick + step + tickSpacing;
        addLiquidityParams.lowerOld = helper.insert(addLiquidityParams.lower);
        addLiquidityParams.upperOld = helper.insert(addLiquidityParams.upper);
        await expect(_addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("WRONG_ORDER");

        // LOWER_RANGE
        addLiquidityParams.lower = -Math.floor(887272 / tickSpacing) * tickSpacing - tickSpacing;
        addLiquidityParams.upper = nearestEvenValidTick + tickSpacing;
        addLiquidityParams.lowerOld = lower;
        addLiquidityParams.upperOld = helper.insert(addLiquidityParams.upper);
        await expect(_addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("TICK_OUT_OF_BOUNDS");

        // UPPER_RANGE
        addLiquidityParams.lower = nearestEvenValidTick;
        addLiquidityParams.upper = Math.floor(887272 / tickSpacing) * tickSpacing + tickSpacing;
        addLiquidityParams.lowerOld = helper.insert(addLiquidityParams.lower);
        addLiquidityParams.upperOld = helper.insert(addLiquidityParams.upper);
        await expect(_addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("TICK_OUT_OF_BOUNDS");

        // LOWER_ORDER - TO DO
        //addLiquidityParams.lower = nearestEvenValidTick;
        //addLiquidityParams.upper = Math.floor(887272 / tickSpacing) * tickSpacing + tickSpacing;
        //addLiquidityParams.lowerOld = helper.insert(addLiquidityParams.lower);
        //addLiquidityParams.upperOld = helper.insert(addLiquidityParams.upper);
        //await expect(_addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("LOWER_ORDER");

        // UPPER_ORDER - TO DO
        //addLiquidityParams.lower = nearestEvenValidTick;
        //addLiquidityParams.upper = Math.floor(887272 / tickSpacing) * tickSpacing + tickSpacing;
        //addLiquidityParams.lowerOld = helper.insert(addLiquidityParams.lower);
        //addLiquidityParams.upperOld = helper.insert(addLiquidityParams.upper);
        //await expect(_addLiquidityViaRouter(addLiquidityParams)).to.be.revertedWith("UPPER_ORDER");
      }
    });

    it("Should fail to burn if overflow", async () => {
      const pool = trident.concentratedPools[0];

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

      lower = 609332;
      upper = lower + 1;

      const tokens = await pool.getAssets();
      const token0BalanceInitial = await Trident.Instance.bento.balanceOf(tokens[0], pool.address);

      await expect(
        pool
          .connect(trident.accounts[4])
          .burn(
            ethers.utils.defaultAbiCoder.encode(
              ["int24", "int24", "uint128", "address", "bool"],
              [lower, upper, BigNumber.from(`2`).pow(128).sub(`1`), trident.accounts[4].address, false]
            )
          )
      ).to.be.revertedWith("overflow");

      // const token0BalanceAfter = await Trident.Instance.bento.balanceOf(tokens[0], pool.address);
      // console.log(token0BalanceAfter.toString())
      // expect(token0BalanceAfter).lt(getBigNumber('1'))
    });
  });
});

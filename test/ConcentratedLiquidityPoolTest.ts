import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
  addLiquidityViaRouter,
  collectFees,
  collectProtocolFee,
  getDx,
  getDy,
  getTickAtCurrentPrice,
  LinkedListHelper,
  swapViaRouter,
} from "./harness/Concentrated";
import { getBigNumber } from "./harness/helpers";
import { Trident } from "./harness/Trident";

describe.only("Concentrated Liquidity Product Pool", function () {
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
          recipient: defaultAddress,
        };

        await addLiquidityViaRouter(addLiquidityParams);

        const lowerPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(lower);
        const currentPrice = await pool.price();
        const maxDx = await getDx(await pool.liquidity(), lowerPrice, currentPrice, false);

        // swap back and forth
        const output = await swapViaRouter({
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
          inAmount: output,
          recipient: defaultAddress,
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

        const currentPrice = await pool.price();
        const upperPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(upper);
        const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);

        const output = await swapViaRouter({
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
          inAmount: output,
          recipient: defaultAddress,
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

        const currentPrice = await pool.price();
        const upperPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(upper);
        const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);

        const output = await swapViaRouter({
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
          inAmount: output,
          recipient: defaultAddress,
        });
      }
    });

    it("Should distribute fees correctly", async () => {
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
          recipient: defaultAddress,
        };

        const tokenIdA = (await addLiquidityViaRouter(addLiquidityParams)).tokenId;

        addLiquidityParams.amount0Desired = addLiquidityParams.amount0Desired.mul(2);
        addLiquidityParams.amount1Desired = addLiquidityParams.amount1Desired.mul(2);
        const tokenIdB = (await addLiquidityViaRouter(addLiquidityParams)).tokenId;

        addLiquidityParams = helper.setTicks(lower - step * 2, upper - step * 2, addLiquidityParams);
        const tokenIdC = (await addLiquidityViaRouter(addLiquidityParams)).tokenId;

        // swap within tick
        const currentPrice = await pool.price();
        const upperPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(upper);
        const maxDy = await getDy(await pool.liquidity(), currentPrice, upperPrice, false);

        let output = await swapViaRouter({
          pool: pool,
          unwrapBento: true,
          zeroForOne: false,
          inAmount: maxDy,
          recipient: defaultAddress,
        });

        output = await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: true,
          inAmount: output,
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

        output = await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: false,
          inAmount: output,
          recipient: defaultAddress,
        });

        await swapViaRouter({
          pool: pool,
          unwrapBento: false,
          zeroForOne: true,
          inAmount: output,
          recipient: defaultAddress,
        });

        const smallerPositionFees2 = await collectFees({ pool, tokenId: tokenIdA, recipient: defaultAddress, unwrapBento: false });

        const smallerPositionFeesDy = smallerPositionFees2.dy.add(smallerPositionFees1.dy);
        const smallerPositionFeesDx = smallerPositionFees2.dx.add(smallerPositionFees1.dx);
        const biggerPositionFees = await collectFees({ pool, tokenId: tokenIdB, recipient: defaultAddress, unwrapBento: false });
        const outsidePositionFees = await collectFees({ pool, tokenId: tokenIdC, recipient: defaultAddress, unwrapBento: false });
        expect(smallerPositionFeesDy.div(100).toString()).to.be.eq(
          biggerPositionFees.dy.div(100).div(2).toString(),
          "fees 0 weren't proportionally split"
        ); // divide by 100 (remove 2 decimal places) to ignore 1 raw rounding errors
        expect(smallerPositionFeesDx.div(100).toString()).to.be.eq(
          biggerPositionFees.dx.div(100).div(2).toString(),
          "fees 1 weren't proportionally split"
        );
        expect(outsidePositionFees.dy.toString()).to.be.eq("0", "fees were acredited to a position not in range");
      }
    });

    it("Should collect protocolFee", async () => {
      for (const pool of trident.concentratedPools) {
        helper.reset();

        const tickSpacing = await pool.tickSpacing();
        const tickAtPrice = await getTickAtCurrentPrice(pool);
        const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
        const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;
        const token0 = await pool.token0();
        const token1 = await pool.token1();
        const barFeeTo = await pool.barFeeTo();
        const oldBarFeeToBalanceToken0 = await Trident.Instance.bento.balanceOf(token0, barFeeTo);
        const oldBarFeeToBalanceToken1 = await Trident.Instance.bento.balanceOf(token1, barFeeTo);

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

        const lowerPrice = await Trident.Instance.tickMath.getSqrtRatioAtTick(lower);
        const currentPrice = await pool.price();
        const maxDx = await getDx(await pool.liquidity(), lowerPrice, currentPrice, false);

        // swap back and forth
        const output = await swapViaRouter({
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
          inAmount: output,
          recipient: defaultAddress,
        });

        const { token0ProtocolFee, token1ProtocolFee } = await collectProtocolFee({ pool: pool });
        const barFeeToBalanceToken0 = await Trident.Instance.bento.balanceOf(token0, barFeeTo);
        const barFeeToBalanceToken1 = await Trident.Instance.bento.balanceOf(token1, barFeeTo);

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

    it.skip("Should burn the position and receive tokens back", async () => {});

    it.skip("Should create incentive", async () => {});
  });

  describe("Invalid actions", async () => {
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

        // TODO: WRONG_ORDER, LOWER_RANGE, UPPER_RANGE
        // TODO: invalid lower old & upper old ticks
      }
    });
  });
});

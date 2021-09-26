import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { getBigNumber } from "@sushiswap/sdk";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ConcentratedLiquidityPool, ConcentratedLiquidityPoolManager, TridentRouter } from "../../types";
import { swap } from "./ConstantProduct";
import { divRoundingUp } from "./helpers";
import { Trident } from "./Trident";

const TWO_POW_96 = BigNumber.from(2).pow(96);
const TWO_POW_128 = BigNumber.from(2).pow(128);

export async function swapViaRouter(params: {
  pool: ConcentratedLiquidityPool;
  zeroForOne: boolean; // true => we are moving left
  inAmount: BigNumber;
  recipient: string;
  unwrapBento: boolean;
}): Promise<BigNumber> {
  const { pool, zeroForOne, inAmount, recipient, unwrapBento } = params;
  const nearest = await pool.nearestTick();

  let nextTickToCross = zeroForOne ? nearest : (await pool.ticks(nearest)).nextTick;
  let currentPrice = await pool.price();
  let currentLiquidity = await pool.liquidity();
  let input = inAmount;
  let output = BigNumber.from(0);
  let feeGrowthGlobalIncrease = BigNumber.from(0);
  let crossCount = 0;
  let protocolFeeIncrease = BigNumber.from(0);

  const oldPrice = currentPrice;
  const tokens = await Promise.all([pool.token0(), pool.token1()]);
  const [swapFee, barFee] = await Promise.all([pool.swapFee(), pool.barFee()]);
  const feeGrowthGlobalOld = await (zeroForOne ? pool.feeGrowthGlobal1() : pool.feeGrowthGlobal0());
  const oldProtocolFees = await (zeroForOne ? pool.token1ProtocolFee() : pool.token0ProtocolFee());
  // TODO add balance update check

  while (input.gt(0)) {
    const nextTickPrice = await getTickPrice(nextTickToCross);
    let cross = false;
    let stepOutput;
    let newPrice;

    if (zeroForOne) {
      const maxDx = await getDx(currentLiquidity, nextTickPrice, currentPrice, false);

      if (input.lte(maxDx)) {
        const liquidityPadded = currentLiquidity.mul(TWO_POW_96);
        newPrice = divRoundingUp(liquidityPadded.mul(currentPrice), liquidityPadded.add(currentPrice.mul(input)));
        stepOutput = getDy(currentLiquidity, newPrice, currentPrice, false);
        currentPrice = newPrice;
        input = BigNumber.from(0);
      } else {
        stepOutput = getDy(currentLiquidity, nextTickPrice, currentPrice, false);
        currentPrice = nextTickPrice;
        input = input.sub(maxDx);
        cross = true;
      }
    } else {
      // (price) numba' go up
      const maxDy = await getDy(currentLiquidity, currentPrice, nextTickPrice, false);
      if (input.lte(maxDy)) {
        newPrice = currentPrice.add(input.mul(TWO_POW_96).div(currentLiquidity));
        stepOutput = getDx(currentLiquidity, currentPrice, newPrice, false);
        currentPrice = newPrice;
        input = BigNumber.from(0);
      } else {
        stepOutput = getDx(currentLiquidity, currentPrice, nextTickPrice, false);
        currentPrice = nextTickPrice;
        input = input.sub(maxDy);
        cross = true;
      }
    }

    if (currentLiquidity.gt(0)) {
      const feeAmount = divRoundingUp(stepOutput.mul(swapFee), BigNumber.from(1e6));
      const protocolFee = divRoundingUp(feeAmount.mul(barFee), BigNumber.from(1e4));
      protocolFeeIncrease = protocolFeeIncrease.add(protocolFee);
      feeGrowthGlobalIncrease = feeGrowthGlobalIncrease.add(feeAmount.sub(protocolFee).mul(TWO_POW_128).div(currentLiquidity));
      output = output.add(stepOutput.sub(feeAmount));
    }

    if (cross) {
      crossCount++;
      const liquidityChange = (await pool.ticks(nextTickToCross)).liquidity;
      const tickInfo = await pool.ticks(nextTickToCross);
      // TODO if we run out of liquidity (tick == min | tick =0 max tick) we need to throw an error here
      if (zeroForOne) {
        if (nextTickToCross % 2 == 0) {
          currentLiquidity = currentLiquidity.sub(liquidityChange);
        } else {
          currentLiquidity = currentLiquidity.add(liquidityChange);
        }
        nextTickToCross = tickInfo.previousTick;
      } else {
        if (nextTickToCross % 2 == 0) {
          currentLiquidity = currentLiquidity.add(liquidityChange);
        } else {
          currentLiquidity = currentLiquidity.sub(liquidityChange);
        }
        nextTickToCross = tickInfo.nextTick;
      }
    }
  }

  const swapData = getSwapData({ zeroForOne, inAmount, recipient, unwrapBento });
  const routerData = {
    amountIn: inAmount,
    amountOutMinimum: output,
    pool: pool.address,
    tokenIn: zeroForOne ? tokens[0] : tokens[1],
    data: swapData,
  };

  await Trident.Instance.router.exactInputSingle(routerData);

  const feeGrowthGlobalnew = await (zeroForOne ? pool.feeGrowthGlobal1() : pool.feeGrowthGlobal0());
  const protocolFeesNew = await (zeroForOne ? pool.token1ProtocolFee() : pool.token0ProtocolFee());
  const newPrice = await pool.price();

  let nextNearest = nearest;
  for (let i = 0; i < crossCount; i++) {
    nextNearest = (await pool.ticks(nextNearest))[zeroForOne ? "previousTick" : "nextTick"];
  }

  // TODO check balannce changes and reserve changes are correct!
  expect((await pool.liquidity()).toString()).to.be.eq(currentLiquidity.toString(), "didn't set correct liquidity value");
  expect(await pool.nearestTick()).to.be.eq(nextNearest, "didn't update nearest tick pointer");
  expect(oldPrice.lt(newPrice) !== zeroForOne, "Price didn't move in the right direction");
  expect(protocolFeesNew.toString()).to.be.eq(
    oldProtocolFees.add(protocolFeeIncrease).toString(),
    "Didn't update protocol fee counter correctly"
  );
  expect(feeGrowthGlobalnew.toString()).to.be.eq(
    feeGrowthGlobalOld.add(feeGrowthGlobalIncrease).toString(),
    "Didn't update the global fee tracker"
  );
  return output;
}

export async function removeLiquidityViaManager(params: {
  tokenId: number;
  liquidityAmount: BigNumber;
  recipient: string;
  unwrapBento: boolean;
}): Promise<{ token0: BigNumber; token1: BigNumber }> {
  const { tokenId, liquidityAmount, recipient, unwrapBento } = params;
  await Trident.Instance.concentratedPoolManager.burn(tokenId, liquidityAmount, recipient, unwrapBento);
  return { token0: BigNumber.from(0), token1: BigNumber.from(1) };
}

export async function addLiquidityViaRouter(params: {
  pool: ConcentratedLiquidityPool;
  amount0Desired: BigNumber;
  amount1Desired: BigNumber;
  native: boolean;
  lowerOld: BigNumber | number;
  lower: BigNumber | number;
  upperOld: BigNumber | number;
  upper: BigNumber | number;
  positionOwner: string;
  recipient: string;
}): Promise<{ dy: BigNumber; dx: BigNumber }> {
  const { pool, amount0Desired, amount1Desired, native, lowerOld, lower, upperOld, upper, positionOwner, recipient } = params;
  const [currentPrice, priceLower, priceUpper] = await getPrices(pool, [lower, upper]);
  const liquidity = getLiquidityForAmount(priceLower, currentPrice, priceUpper, amount1Desired, amount0Desired);
  const tokens = await Promise.all([pool.token0(), pool.token1()]);
  const oldUserBalances = await Trident.Instance.getTokenBalance(tokens, recipient, native);
  const oldPoolBalances = await Trident.Instance.getTokenBalance(tokens, pool.address, false);
  const oldLiquidity = await pool.liquidity();
  const oldTotalSupply = await Trident.Instance.concentratedPoolManager.totalSupply();
  const liquidityIncrease = priceLower.lt(currentPrice) && currentPrice.lt(priceUpper) ? liquidity : "0";
  const { dy, dx } = getAmountForLiquidity(priceLower, currentPrice, priceUpper, liquidity);
  const [oldLowerOldPreviousTick, oldLowerOldNextTick, oldLowerOldLiquidity] = await pool.ticks(lowerOld);
  const [oldUpperOldPreviousTick, oldUpperOldNextTick, oldUpperOldLiquidity] = await pool.ticks(upperOld);
  const [oldLowerPreviousTick, oldLowerNextTick, oldLowerLiquidity] = await pool.ticks(lower);
  const [oldUpperPreviousTick, oldUpperNextTick, oldUpperLiquidity] = await pool.ticks(upper);
  const oldPositionState = await pool.positions(positionOwner, lower, upper);
  const mintData = getMintData({
    lowerOld,
    lower,
    upperOld,
    upper,
    amount0Desired,
    amount1Desired,
    native0: native,
    native1: native,
    positionOwner,
    recipient: recipient,
  });
  await Trident.Instance.router.addLiquidityLazy(pool.address, liquidity, mintData);

  const newLiquidity = await pool.liquidity();
  const newPrice = await pool.price();
  const newTotalSupply = await Trident.Instance.concentratedPoolManager.totalSupply();
  const newUserBalances = await Trident.Instance.getTokenBalance(tokens, recipient, native);
  const newPoolBalances = await Trident.Instance.getTokenBalance(tokens, pool.address, false);
  const newPositionState = await pool.positions(positionOwner, lower, upper);
  const [newLowerOldPreviousTick, newLowerOldNextTick, newLowerOldLiquidity] = await pool.ticks(lowerOld);
  const [newUpperOldPreviousTick, newUpperOldNextTick, newUpperOldLiquidity] = await pool.ticks(upperOld);
  const [newLowerPreviousTick, newLowerNextTick, newLowerLiquidity] = await pool.ticks(lower);
  const [newUpperPreviousTick, newUpperNextTick, newUpperLiquidity] = await pool.ticks(upper);

  expect(newPrice.toString()).to.be.eq(currentPrice.toString(), "price changed by mistake");
  expect(newLiquidity.toString()).to.be.eq(oldLiquidity.add(liquidityIncrease).toString(), "Liquidity didn't update correctly");
  expect(newLowerOldPreviousTick).to.be.eq(oldLowerOldPreviousTick, "Mistakenly updated previous pointer of lowerOld");
  expect(newPositionState.liquidity.toString()).to.be.eq(
    oldPositionState.liquidity.add(liquidity).toString(),
    "didn't correctly update position's liquidity"
  );
  expect(newPositionState.feeGrowthInside0Last.toString()).to.be.eq("0", "didn't reset position's fee0 growth");
  expect(newPositionState.feeGrowthInside1Last.toString()).to.be.eq("0", "didn't reset position's fee1 growth");

  if (oldLowerLiquidity.gt(0)) {
    // existing tick, lowerOld shouldn't get updated
    expect(newLowerLiquidity.toString()).to.be.eq(
      oldLowerLiquidity.add(liquidity).toString(),
      "Didn't increase lower tick liquidity by the right amount"
    );
    expect(newLowerPreviousTick).to.be.eq(oldLowerPreviousTick, "Previous tick mistekenly updated");
  } else {
    // new tick, lowerOld should get updated
    expect(newLowerLiquidity.toString()).to.be.eq(liquidity.toString(), "Didn't set correct liqiuidity value on new tick");
    expect(newLowerOldNextTick).to.be.eq(lower, "Old not pointing to new");
    expect(newLowerPreviousTick).to.be.eq(lowerOld, "New tick now pointing to old");
  }

  if (oldUpperLiquidity.gt(0)) {
    // existing tick, upperOld shouldn't get updated
    expect(newUpperLiquidity.toString()).to.be.eq(
      oldUpperLiquidity.add(liquidity).toString(),
      "Didn't increase upper tick liquidity by the right amount"
    );
    expect(newUpperNextTick).to.be.eq(oldUpperNextTick, "Next tick pointer mistekenly updated");
  } else {
    // new tick
    expect(newUpperLiquidity.toString()).to.be.eq(liquidity.toString(), "Didn't set correct liqiuidity value on new tick");
    expect(newUpperOldNextTick).to.be.eq(upper, "Old tick not pointing to the new");
    expect(newUpperPreviousTick).to.be.eq(upperOld, "New Tick not pointing to the old");
  }
  expect(newUserBalances[0].toString()).to.be.eq(oldUserBalances[0].sub(dx).toString(), "Didn't pay correct amount of token0");
  expect(newUserBalances[1].toString()).to.be.eq(oldUserBalances[1].sub(dy).toString(), "Didn't pay correct amount of token1");
  expect(newPoolBalances[0].toString()).to.be.eq(oldPoolBalances[0].add(dx).toString(), "Didn't receive correct amount of token0");
  expect(newPoolBalances[1].toString()).to.be.eq(oldPoolBalances[1].add(dy).toString(), "Didn't receive correct amount of token1");
  if (positionOwner === Trident.Instance.concentratedPoolManager.address) {
    expect(oldTotalSupply.add(1).toString()).to.be.eq(newTotalSupply.toString(), "nft wasn't minted");
    const [_pool, _liquidity, _lower, _upper, _feeGrowth0, _feeGrowth1] = await Trident.Instance.concentratedPoolManager.positions(
      oldTotalSupply
    );
    const nftOwner = await Trident.Instance.concentratedPoolManager.ownerOf(oldTotalSupply);
    expect(nftOwner).to.be.eq(recipient, "ower doesn't receive the nft position");
    expect(_pool).to.be.eq(pool.address, "position isn't of the correct pool");
    expect(_lower).to.be.eq(lower, "position doesn't have the correct lower tick");
    expect(_upper).to.be.eq(upper, "position doesn't have the correct upper tick");
    expect(_liquidity).to.be.eq(liquidity, "position doens't have the minted liquidity");
    // TODO check pool reserve change is correct!
    // TODO add function to calculate range fee growth here and ensure that positionManager saved the correct value
  }
  return { dy, dx };
}

// use solidity here for convenience
export function getPrices(pool: ConcentratedLiquidityPool, ticks: Array<BigNumber | number>) {
  const trident: Trident = Trident.Instance;
  return Promise.all([pool.price(), ...ticks.map((tick) => trident.tickMath.getSqrtRatioAtTick(tick))]);
}

export function getTickPrice(tick) {
  return Trident.Instance.tickMath.getSqrtRatioAtTick(tick);
}

export function getLiquidityForAmount(priceLower: BigNumber, currentPrice: BigNumber, priceUpper: BigNumber, dy: BigNumber, dx: BigNumber) {
  if (priceUpper.lt(currentPrice)) {
    return dy.mul("0x1000000000000000000000000").div(priceUpper.sub(priceLower));
  } else if (currentPrice.lt(priceLower)) {
    return dx.mul(priceLower.mul(priceUpper).div("0x1000000000000000000000000")).div(priceUpper.sub(priceLower));
  } else {
    const liquidity0 = dx.mul(priceUpper.mul(currentPrice).div("0x1000000000000000000000000")).div(priceUpper.sub(currentPrice));
    const liquidity1 = dy.mul("0x1000000000000000000000000").div(currentPrice.sub(priceLower));
    return liquidity0.lt(liquidity1) ? liquidity0 : liquidity1;
  }
}

export function getAmountForLiquidity(priceLower: BigNumber, currentPrice: BigNumber, priceUpper: BigNumber, liquidity: BigNumber) {
  if (priceUpper.lt(currentPrice)) {
    return {
      dy: getDy(liquidity, priceLower, priceUpper, true),
      dx: BigNumber.from(0),
    };
  } else if (currentPrice.lt(priceLower)) {
    return {
      dy: BigNumber.from(0),
      dx: getDx(liquidity, priceLower, priceUpper, true),
    };
  } else {
    return {
      dy: getDy(liquidity, priceLower, currentPrice, true),
      dx: getDx(liquidity, currentPrice, priceUpper, true),
    };
  }
}

export function getSwapData(params: { zeroForOne: boolean; inAmount: BigNumber; recipient: string; unwrapBento: boolean }) {
  const { zeroForOne, inAmount, recipient, unwrapBento } = params;
  return ethers.utils.defaultAbiCoder.encode(["bool", "uint256", "address", "bool"], [zeroForOne, inAmount, recipient, unwrapBento]);
}

export function getMintData(params: {
  lowerOld: BigNumber | number;
  lower: BigNumber | number;
  upperOld: BigNumber | number;
  upper: BigNumber | number;
  amount0Desired: BigNumber;
  amount1Desired: BigNumber;
  native0: boolean;
  native1: boolean;
  positionOwner: string;
  recipient: string;
}) {
  const { lowerOld, lower, upperOld, upper, amount0Desired, amount1Desired, native0, native1, positionOwner, recipient } = params;
  return ethers.utils.defaultAbiCoder.encode(
    ["int24", "int24", "int24", "int24", "uint256", "uint256", "bool", "bool", "address", "address"],
    [lowerOld, lower, upperOld, upper, amount0Desired, amount1Desired, native0, native1, positionOwner, recipient]
  );
}

export async function getTickAtCurrentPrice(pool: ConcentratedLiquidityPool) {
  return getTickAtPrice(await pool.price());
}

export function getTickAtPrice(price: BigNumber) {
  return Trident.Instance.tickMath.getTickAtSqrtRatio(price);
}

export function getDy(liquidity: BigNumber, priceLower: BigNumber, priceUpper: BigNumber, roundUp: boolean) {
  if (roundUp) {
    return divRoundingUp(liquidity.mul(priceUpper.sub(priceLower)), BigNumber.from("0x1000000000000000000000000"));
  } else {
    return liquidity.mul(priceUpper.sub(priceLower)).div("0x1000000000000000000000000");
  }
}

export function getDx(liquidity: BigNumber, priceLower: BigNumber, priceUpper: BigNumber, roundUp: boolean) {
  if (roundUp) {
    return divRoundingUp(liquidity.mul("0x1000000000000000000000000").mul(priceUpper.sub(priceLower)).div(priceUpper), priceLower);
  } else {
    return liquidity.mul("0x1000000000000000000000000").mul(priceUpper.sub(priceLower)).div(priceUpper).div(priceLower);
  }
}

export class LinkedListHelper {
  min: number;
  values: number[] = [];
  constructor(min: number) {
    this.min = min;
    this.reset();
  }

  // insert a tick in the linked list; return what the previous tick was
  // if thick already exists just return it
  insert(tick) {
    let old = this.values[0];
    let i = 0;
    while (++i < this.values.length) {
      if (this.values[i] < tick) old = this.values[i];
    }
    if (!this.values.includes(tick)) {
      this.values.push(tick);
      this.values = this.values.sort((a, b) => a - b);
    }
    return old;
  }

  reset() {
    this.values = [this.min];
  }

  setTicks(lower, upper, params) {
    params.lower = lower;
    params.upper = upper;
    params.lowerOld = this.insert(lower);
    params.upperOld = this.insert(upper);
    return params;
  }
}

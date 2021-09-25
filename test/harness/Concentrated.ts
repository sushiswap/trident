import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ConcentratedLiquidityPool, TridentRouter } from "../../types";
import { swap } from "./ConstantProduct";
import { Trident } from "./Trident";

const TWO_POW_96 = BigNumber.from(2).pow(96);
const TWO_POW_128 = BigNumber.from(2).pow(128);

export async function swapViaRouter(params: {
  pool: ConcentratedLiquidityPool;
  zeroForOne: boolean; // true => we are moving left
  inAmount: BigNumber;
  recipient: string;
  unwrapBento: boolean;
}) {
  const { pool, zeroForOne, inAmount, recipient, unwrapBento } = params;
  const nearest = await pool.nearestTick();
  let nextTickToCross = zeroForOne ? nearest : (await pool.ticks(nearest)).nextTick;
  let currentPrice = await pool.price();
  const oldPrice = currentPrice;
  let currentLiquidity = await pool.liquidity();
  let input = inAmount;
  let output = BigNumber.from(0);
  let feeGrowthGlobalIncrease = BigNumber.from(0);
  let crossCount = 0;
  const tokens = await Promise.all([pool.token0(), pool.token1()]);
  const [swapFee, barFee] = await Promise.all([pool.swapFee(), pool.barFee()]);
  const feeGrowthGlobalOld = await (zeroForOne ? pool.feeGrowthGlobal1() : pool.feeGrowthGlobal0());
  const oldProtocolFees = await (zeroForOne ? pool.token1ProtocolFee() : pool.token0ProtocolFee());
  let protocolFeeIncrease = BigNumber.from(0);
  // todo add balance update check

  while (input.gt(0)) {
    const nextTickPrice = await getTickPrice(nextTickToCross);
    let stepOutput;
    let newPrice;
    let cross = false;

    if (zeroForOne) {
      const maxDx = await getDx(currentLiquidity, nextTickPrice, currentPrice, false);
      if (input.lt(maxDx)) {
        const liquidityPadded = currentLiquidity.mul(TWO_POW_96);
        newPrice = liquidityPadded
          .mul(currentPrice)
          .div(liquidityPadded.add(currentPrice.mul(input)))
          .add(1);
        stepOutput = getDy(currentLiquidity, newPrice, currentPrice, false);
        currentPrice = newPrice;
        input = BigNumber.from(0);
      } else {
        stepOutput = getDy(currentLiquidity, nextTickPrice, currentLiquidity, false);
        currentPrice = nextTickPrice;
        input = input.sub(maxDx);
        cross = true;
      }
    } else {
      // (price) numba' go up
      const maxDy = await getDy(currentLiquidity, currentPrice, nextTickPrice, false);
      if (input.lt(maxDy)) {
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
    const feeAmount = stepOutput.mul(swapFee).div(1e6).add(1); // lazy round up
    const protocolFee = feeAmount.mul(barFee).div(1e4).add(1); // todo - write an accurate function for round up division
    protocolFeeIncrease = protocolFeeIncrease.add(protocolFee);
    feeGrowthGlobalIncrease = feeGrowthGlobalIncrease.add(feeAmount.sub(protocolFee).mul(TWO_POW_128).div(currentLiquidity));
    output = output.add(stepOutput.sub(feeAmount));

    if (cross) {
      crossCount++;
      const liquidityChange = (await pool.ticks(nextTickToCross)).liquidity;
      const tickInfo = await pool.ticks(nextTickToCross);
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
        nextTickToCross = tickInfo.previousTick;
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
  expect((await pool.liquidity()).toString()).to.be.eq(currentLiquidity.toString(), "didn't set correct liquidity value");
  expect(await pool.nearestTick()).to.be.eq(nextNearest, "didn't update nearest tick pointer");
  expect(oldPrice.lt(newPrice) !== zeroForOne, "Price didn't move in the right direction");
  expect(protocolFeesNew.toString()).to.be.eq(oldProtocolFees.add(protocolFeeIncrease).toString(), "didn't update protocol fee counter");
  expect(feeGrowthGlobalnew.toString()).to.be.eq(
    feeGrowthGlobalOld.add(feeGrowthGlobalIncrease).toString(),
    "Didn't update the global fee tracker"
  );
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
}) {
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
  const [_lowerOldPreviousTick, _lowerOldNextTick, _lowerOldLiquidity] = await pool.ticks(lowerOld);
  const [_upperOldPreviousTick, _upperOldNextTick, _upperOldLiquidity] = await pool.ticks(upperOld);
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
  const newTotalSupply = await Trident.Instance.concentratedPoolManager.totalSupply();
  const newUserBalances = await Trident.Instance.getTokenBalance(tokens, recipient, native);
  const newPoolBalances = await Trident.Instance.getTokenBalance(tokens, pool.address, false);
  const [lowerOldPreviousTick, lowerOldNextTick, lowerOldLiquidity] = await pool.ticks(lowerOld);
  const [upperOldPreviousTick, upperOldNextTick, upperOldLiquidity] = await pool.ticks(upperOld);
  const [lowerPreviousTick, lowerNextTick, lowerLiquidity] = await pool.ticks(lower);
  const [upperPreviousTick, upperNextTick, upperLiquidity] = await pool.ticks(upper);

  expect(newLiquidity.toString()).to.be.eq(oldLiquidity.add(liquidityIncrease).toString(), "Liquidity didn't update correctly");
  expect(lowerOldPreviousTick).to.be.eq(_lowerOldPreviousTick, "Mistakenly updated previous pointer of lowerOld");
  if (upper < _lowerOldNextTick) {
    expect(upperNextTick).to.be.eq(_lowerOldNextTick);
  }
  if (lowerOld == lower) {
    expect(lowerOldLiquidity.add(liquidity).toString()).to.be.eq(
      lowerLiquidity.toString(),
      "Didn't increase liquidity by the right amount"
    );
    expect(_lowerOldPreviousTick).to.be.eq(lowerPreviousTick, "Previous tick mistekenly updated");
    expect(_lowerOldNextTick).to.be.eq(lowerNextTick, "Previous tick mistekenly updated");
  } else {
    expect(lowerLiquidity.toString()).to.be.eq(liquidity.toString(), "Didn't set correct liqiuidity value on new tick");
    expect(lowerOld).to.be.eq(lowerPreviousTick, "Previous not pointing to old");
    expect(lowerOldNextTick).to.be.eq(lower, "Next not pointing to new");
  }
  if (upperOld == upper) {
    expect(upperOldLiquidity.add(liquidity).toString()).to.be.eq(
      upperLiquidity.toString(),
      "Didn't increase liquidity by the right amount"
    );
    expect(_upperOldNextTick).to.be.eq(upperNextTick, "Next tick pointer mistekenly updated");
    expect(_upperOldPreviousTick).to.be.eq(upperPreviousTick, "Previous tick pointer mistekenly updated");
  } else {
    expect(upperLiquidity.toString()).to.be.eq(liquidity.toString(), "Didn't set correct liqiuidity value on new tick");
    expect(upperOldNextTick).to.be.eq(upper, "Previous not pointing to old");
    expect(upperPreviousTick).to.be.eq(upperOld, "Next not pointing to new");
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
    // TODO add function to calculate range fee growth here and ensure that positionManager saved the correct value
  }
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
      dx: 0,
    };
  } else if (currentPrice.lt(priceLower)) {
    return {
      dy: 0,
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
  const res = liquidity.mul(priceUpper.sub(priceLower)).div("0x1000000000000000000000000");
  if (roundUp) return res.add(1); // lazy round up
  return res;
}

function getDx(liquidity: BigNumber, priceLower: BigNumber, priceUpper: BigNumber, roundUp: boolean) {
  const res = liquidity.mul("0x1000000000000000000000000").mul(priceUpper.sub(priceLower)).div(priceUpper).div(priceLower);
  if (roundUp) return res.add(1);
  return res;
}

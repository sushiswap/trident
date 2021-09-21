import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ConcentratedLiquidityPool, ConstantProductPool } from "../../types";
import { Trident } from "./Trident";

export async function initialize() {
  return await Trident.Instance.init();
}

export async function addLiquidityViaRouter(
  pool: ConcentratedLiquidityPool,
  token0amount: BigNumber,
  token1amount: BigNumber,
  fromBento: boolean,
  lowerOld: BigNumber | number,
  lower: BigNumber | number,
  upperOld: BigNumber | number,
  upper: BigNumber | number,
  positionOwner: string,
  positionRecipient: string
) {
  const [currentPrice, priceLower, priceUpper] = await getPrices(pool, lower, upper);
  const liquidity = getLiquidityForAmount(priceLower, currentPrice, priceUpper, token1amount, token0amount);
  const mintData = getMintData(
    lowerOld,
    lower,
    upperOld,
    upper,
    token0amount,
    token1amount,
    fromBento,
    fromBento,
    positionOwner,
    positionRecipient
  );
  await Trident.Instance.router.addLiquidityLazy(pool.address, liquidity, mintData);
  // todo: account for prev. liquidity and minting out of range etc
  expect((await pool.liquidity()).toString()).to.be.eq(liquidity.toString());
}

export function getPrices(pool: ConcentratedLiquidityPool, tickLower: BigNumber | number, tickUpper: BigNumber | number) {
  const trident: Trident = Trident.Instance;
  return Promise.all([pool.price(), trident.tickMath.getSqrtRatioAtTick(tickLower), trident.tickMath.getSqrtRatioAtTick(tickUpper)]);
}

export function getLiquidityForAmount(priceLower: BigNumber, currentPrice: BigNumber, priceUpper: BigNumber, dy: BigNumber, dx: BigNumber) {
  if (priceUpper.lt(currentPrice)) {
    return dy.mul("0x1000000000000000000000000").div(priceUpper.sub(priceLower));
  } else if (currentPrice <= priceLower) {
    return dx.mul(priceLower.mul(priceUpper).div("0x1000000000000000000000000")).div(priceUpper.sub(priceLower));
  } else {
    const liquidity0 = dx.mul(priceUpper.mul(currentPrice).div("0x1000000000000000000000000")).div(priceUpper.sub(currentPrice));
    const liquidity1 = dy.mul("0x1000000000000000000000000").div(currentPrice.sub(priceLower));
    return liquidity0.lt(liquidity1) ? liquidity0 : liquidity1;
  }
}

export function getMintData(
  lowerOld: BigNumber | number,
  lower: BigNumber | number,
  upperOld: BigNumber | number,
  upper: BigNumber | number,
  amount0Desired: BigNumber,
  amount1Desired: BigNumber,
  amount0native: boolean,
  amount1native: boolean,
  positionOwner: string,
  recipient: string
) {
  return ethers.utils.defaultAbiCoder.encode(
    ["int24", "int24", "int24", "int24", "uint256", "uint256", "bool", "bool", "address", "address"],
    [lowerOld, lower, upperOld, upper, amount0Desired, amount1Desired, amount0native, amount1native, positionOwner, recipient]
  );
}

export async function getTickAtCurrentPrice(pool: ConcentratedLiquidityPool) {
  return getTickAtPrice(await pool.price());
}

export function getTickAtPrice(price: BigNumber) {
  return Trident.Instance.tickMath.getTickAtSqrtRatio(price);
}

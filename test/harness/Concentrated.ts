import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ConcentratedLiquidityPool } from "../../types";
import { Trident } from "./Trident";

export async function addLiquidityViaRouter(
  pool: ConcentratedLiquidityPool,
  token0amount: BigNumber,
  token1amount: BigNumber,
  native: boolean,
  lowerOld: BigNumber | number,
  lower: BigNumber | number,
  upperOld: BigNumber | number,
  upper: BigNumber | number,
  positionOwner: string,
  positionRecipient: string
) {
  const [currentPrice, priceLower, priceUpper] = await getPrices(pool, lower, upper);
  const liquidity = getLiquidityForAmount(priceLower, currentPrice, priceUpper, token1amount, token0amount);
  const tokens = await Promise.all([pool.token0(), pool.token1()]);
  const oldUserBalances = await Trident.Instance.getTokenBalance(tokens, positionRecipient, native);
  const oldPoolBalances = await Trident.Instance.getTokenBalance(tokens, pool.address, false);
  const oldLiquidity = await pool.liquidity();
  const oldTotalSupply = await Trident.Instance.concentratedPoolManager.totalSupply();
  const liquidityIncrease = priceLower.lt(currentPrice) && currentPrice.lt(priceUpper) ? liquidity : "0";
  const { dy, dx } = getAmountForLiquidity(priceLower, currentPrice, priceUpper, liquidity);
  const [_lowerOldPreviousTick, _lowerOldNextTick, _lowerOldLiquidity] = await pool.ticks(lowerOld);
  const [_upperOldPreviousTick, _upperOldNextTick, _upperOldLiquidity] = await pool.ticks(upperOld);
  const mintData = getMintData(
    lowerOld,
    lower,
    upperOld,
    upper,
    token0amount,
    token1amount,
    native,
    native,
    positionOwner,
    positionRecipient
  );
  await Trident.Instance.router.addLiquidityLazy(pool.address, liquidity, mintData);

  const newLiquidity = await pool.liquidity();
  const newTotalSupply = await Trident.Instance.concentratedPoolManager.totalSupply();
  const newUserBalances = await Trident.Instance.getTokenBalance(tokens, positionRecipient, native);
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
    expect(nftOwner).to.be.eq(positionRecipient, "ower doesn't receive the nft position");
    expect(_pool).to.be.eq(pool.address, "position isn't of the correct pool");
    expect(_lower).to.be.eq(lower, "position doesn't have the correct lower tick");
    expect(_upper).to.be.eq(upper, "position doesn't have the correct upper tick");
    expect(_liquidity).to.be.eq(liquidity, "position doens't have the minted liquidity");
    // TODO add function to calculate range fee growth here and ensure that positionManager saved the correct value
  }
}

// use solidity here for convenience
export function getPrices(pool: ConcentratedLiquidityPool, tickLower: BigNumber | number, tickUpper: BigNumber | number) {
  const trident: Trident = Trident.Instance;
  return Promise.all([pool.price(), trident.tickMath.getSqrtRatioAtTick(tickLower), trident.tickMath.getSqrtRatioAtTick(tickUpper)]);
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

export function getDy(liquidity: BigNumber, priceLower: BigNumber, priceUpper: BigNumber, roundUp: boolean) {
  const res = liquidity.mul(priceUpper.sub(priceLower)).div("0x1000000000000000000000000");
  if (roundUp) return res.add(1);
  return res;
}

function getDx(liquidity: BigNumber, priceLower: BigNumber, priceUpper: BigNumber, roundUp: boolean) {
  const res = liquidity.mul("0x1000000000000000000000000").mul(priceUpper.sub(priceLower)).div(priceUpper).div(priceLower);
  if (roundUp) return res.add(1);
  return res;
}

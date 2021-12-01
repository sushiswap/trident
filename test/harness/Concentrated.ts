import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { ContractTransaction } from "@ethersproject/contracts";
import { Transaction } from "@ethersproject/transactions";
import { getBigNumber } from "@sushiswap/sdk";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ConcentratedLiquidityPool, ConcentratedLiquidityPoolManager, TridentRouter } from "../../types";
import { ADDRESS_ZERO } from "../utilities";
import { swap } from "./ConstantProduct";
import { divRoundingUp, expectAlmostEqual, ZERO } from "./helpers";
import { Trident } from "./Trident";

export const TWO_POW_96 = BigNumber.from(2).pow(96);
export const TWO_POW_128 = BigNumber.from(2).pow(128);

export async function collectProtocolFee(params: { pool: ConcentratedLiquidityPool }) {
  const { pool } = params;
  const oldTokenProtocolFee = await pool.getTokenProtocolFees();
  const oldToken0ProtocolFee = oldTokenProtocolFee._token0ProtocolFee;
  const oldToken1ProtocolFee = oldTokenProtocolFee._token1ProtocolFee;
  const oldReserve = await pool.getReserves();
  const oldReserve0 = oldReserve._reserve0;
  const oldReserve1 = oldReserve._reserve1;

  await pool.collectProtocolFee();

  const tokenProtocolFee = await pool.getTokenProtocolFees();
  const token0ProtocolFee = tokenProtocolFee._token0ProtocolFee;
  const token1ProtocolFee = tokenProtocolFee._token1ProtocolFee;
  const reserve = await pool.getReserves();
  const reserve0 = reserve._reserve0;
  const reserve1 = reserve._reserve1;

  expect(token0ProtocolFee.toString()).to.be.eq("1", "didn't update the protocol fee 0");
  expect(token1ProtocolFee.toString()).to.be.eq("1", "didn't update the protocol fee 0");
  expect(reserve0.toString()).to.be.eq(
    oldReserve0.sub(oldToken0ProtocolFee).add(BigNumber.from(1)),
    "didn't update the reserve0 correctly"
  );
  expect(reserve1.toString()).to.be.eq(
    oldReserve1.sub(oldToken1ProtocolFee).add(BigNumber.from(1)),
    "didn't update the reserve1 correctly"
  );
  return { token0ProtocolFee: oldToken0ProtocolFee.sub(BigNumber.from(1)), token1ProtocolFee: oldToken1ProtocolFee.sub(BigNumber.from(1)) };
}

export async function collectFees(params: {
  pool: ConcentratedLiquidityPool;
  tokenId: number | BigNumber;
  recipient: string;
  unwrapBento: boolean;
}) {
  const { pool, tokenId, recipient, unwrapBento } = params;
  const position = await Trident.Instance.concentratedPoolManager.positions(tokenId);
  const range = await pool.rangeFeeGrowth(position.lower, position.upper);
  const token0feeGrowth = range.feeGrowthInside0.sub(position.feeGrowthInside0);
  const token1feeGrowth = range.feeGrowthInside1.sub(position.feeGrowthInside1);
  const token0expected = token0feeGrowth.mul(position.liquidity).div(TWO_POW_128);
  const token1expected = token1feeGrowth.mul(position.liquidity).div(TWO_POW_128);
  const immutables = await pool.getImmutables();
  const tokens = [immutables._token0, immutables._token1];
  const oldUserBalances = await Trident.Instance.getTokenBalance(tokens, recipient, false);

  await Trident.Instance.concentratedPoolManager.collect(tokenId, recipient, unwrapBento);

  const nwePosition = await Trident.Instance.concentratedPoolManager.positions(tokenId);
  const newUserBalances = await Trident.Instance.getTokenBalance(tokens, recipient, false);
  expect(nwePosition.feeGrowthInside0.toString()).to.be.eq(range.feeGrowthInside0.toString(), "didn't update fee growth to correct value");
  expect(nwePosition.feeGrowthInside1.toString()).to.be.eq(range.feeGrowthInside1.toString(), "didn't update fee growth to correct value");
  expect(newUserBalances[0].div(100).toString()).to.be.eq(
    oldUserBalances[0].add(token0expected).div(100).toString(),
    "didn't credit token0 fees"
  );
  expect(newUserBalances[1].div(100).toString()).to.be.eq(
    oldUserBalances[1].add(token1expected).div(100).toString(),
    "didn't credit token1 fees"
  );

  await Trident.Instance.concentratedPoolManager.collect(tokenId, recipient, unwrapBento);

  const newerUserBalances = await Trident.Instance.getTokenBalance(tokens, recipient, false);
  expect(newerUserBalances[0].toString()).to.be.eq(newUserBalances[0].toString(), "double dipping");
  expect(newerUserBalances[1].toString()).to.be.eq(newUserBalances[1].toString(), "double dipping");
  return { dx: token0expected, dy: token0expected };
}

export async function swapViaRouter(params: {
  pool: ConcentratedLiquidityPool;
  zeroForOne: boolean; // true => we are moving left
  inAmount: BigNumber;
  recipient: string;
  unwrapBento: boolean;
}): Promise<{ output: BigNumber; tx: ContractTransaction }> {
  const { pool, zeroForOne, inAmount, recipient, unwrapBento } = params;
  const immutables = await pool.getImmutables();
  const nearest = (await pool.getPriceAndNearestTicks())._nearestTick;
  const oldSplData = await pool.getSecondsGrowthAndLastObservation();
  let nextTickToCross = zeroForOne ? nearest : (await pool.ticks(nearest)).nextTick;
  let currentPrice = (await pool.getPriceAndNearestTicks())._price;
  let currentLiquidity = await pool.liquidity();
  let input = inAmount;
  let output = BigNumber.from(0);
  let feeGrowthGlobalIncrease = BigNumber.from(0);
  let crossCount = 0;
  let totalFees = BigNumber.from(0);
  let protocolFeeIncrease = BigNumber.from(0);

  const oldPrice = currentPrice;
  const tokens = [immutables._token0, immutables._token1];
  const swapFee = immutables._swapFee;
  const tickSpacing = immutables._tickSpacing;
  const barFee = await pool.barFee();
  const feeGrowthGlobalOld = await (zeroForOne ? pool.feeGrowthGlobal1() : pool.feeGrowthGlobal0());
  const _oldProtocolFees = await pool.getTokenProtocolFees();
  const oldProtocolFees = zeroForOne ? _oldProtocolFees._token1ProtocolFee : _oldProtocolFees._token0ProtocolFee;
  const oldPoolBalances = await Trident.Instance.getTokenBalance(tokens, pool.address, false);
  const reserve = await pool.getReserves();
  const oldReserve0 = reserve._reserve0;
  const oldReserve1 = reserve._reserve1;
  const startingLiquidity = currentLiquidity;

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
      totalFees = totalFees.add(feeAmount);
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
        if ((nextTickToCross / tickSpacing) % 2 == 0) {
          currentLiquidity = currentLiquidity.sub(liquidityChange);
        } else {
          currentLiquidity = currentLiquidity.add(liquidityChange);
        }
        nextTickToCross = tickInfo.previousTick;
      } else {
        if ((nextTickToCross / tickSpacing) % 2 == 0) {
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

  const tx = await Trident.Instance.router.exactInputSingle(routerData);
  const newSplData = await pool.getSecondsGrowthAndLastObservation();
  const block = await ethers.provider.getBlock(tx.blockNumber as number);
  const timeDiff = block.timestamp - oldSplData._lastObservation;
  const splIncrease = TWO_POW_128.mul(timeDiff).div(startingLiquidity);
  expect(newSplData._secondsGrowthGlobal.toString()).to.be.eq(
    oldSplData._secondsGrowthGlobal.add(splIncrease).toString(),
    "Didn't correctly update global spl counter"
  );
  expect(newSplData._lastObservation).to.be.eq(block.timestamp);
  const feeGrowthGlobalnew = await (zeroForOne ? pool.feeGrowthGlobal1() : pool.feeGrowthGlobal0());
  const _newProtocolFees = await pool.getTokenProtocolFees();
  const protocolFeesNew = zeroForOne ? _newProtocolFees._token1ProtocolFee : _newProtocolFees._token0ProtocolFee;
  const newPrice = (await pool.getPriceAndNearestTicks())._price;
  const newPoolBalances = await Trident.Instance.getTokenBalance(tokens, pool.address, false);
  const [newReserve0, newReserve1] = await pool.getReserves();

  let nextNearest = nearest;
  for (let i = 0; i < crossCount; i++) {
    nextNearest = (await pool.ticks(nextNearest))[zeroForOne ? "previousTick" : "nextTick"];
  }

  expect(newPoolBalances[0].toString()).to.be.eq(
    oldPoolBalances[0].add(zeroForOne ? inAmount : output.mul(-1)).toString(),
    "didn't transfer the correct token 0 amount"
  );
  expect(newPoolBalances[1].toString()).to.be.eq(
    oldPoolBalances[1].add(zeroForOne ? output.mul(-1) : inAmount).toString(),
    "didn't transfer the correct token 1 amount"
  );
  expect(newReserve0.toString()).to.be.eq(oldReserve0.add(zeroForOne ? inAmount : output.mul(-1)), "Didn't update reserve0 correctly");
  expect(newReserve1.toString()).to.be.eq(oldReserve1.add(zeroForOne ? output.mul(-1) : inAmount), "Didn't update reserve1 correctly");
  expect((await pool.liquidity()).toString()).to.be.eq(currentLiquidity.toString(), "didn't set correct liquidity value");
  expect(await (await pool.getPriceAndNearestTicks())._nearestTick).to.be.eq(nextNearest, "didn't update nearest tick pointer");
  expect(oldPrice.lt(newPrice) !== zeroForOne, "Price didn't move in the right direction");
  expect(protocolFeesNew.toString()).to.be.eq(
    oldProtocolFees.add(protocolFeeIncrease).toString(),
    "Didn't update protocol fee counter correctly"
  );
  expect(feeGrowthGlobalnew.toString()).to.be.eq(
    feeGrowthGlobalOld.add(feeGrowthGlobalIncrease).toString(),
    "Didn't update the global fee tracker"
  );
  return { output, tx };
}

export async function removeLiquidityViaManager(params: {
  pool: ConcentratedLiquidityPool;
  tokenId: number;
  liquidityAmount: BigNumber;
  recipient: string;
  unwrapBento: boolean;
}): Promise<{ token0: BigNumber; token1: BigNumber }> {
  const { pool, tokenId, liquidityAmount, recipient, unwrapBento } = params;
  const manager = Trident.Instance.concentratedPoolManager;
  const oldOwner = await Trident.Instance.concentratedPoolManager.ownerOf(tokenId);
  const [oldPoolAddress, oldUserLiquidity, oldLower, oldUpper, oldFeeGrowthInside0, oldFeeGrowthInside1] = await manager.positions(tokenId);
  const [oldCurrentPrice, oldPriceLower, oldPriceUpper] = await getPrices(pool, [oldLower, oldUpper]);
  const tokens = await Promise.all([(await pool.getImmutables())._token0, (await pool.getImmutables())._token1]);
  const oldUserBalances = await Trident.Instance.getTokenBalance(tokens, recipient, unwrapBento);
  const oldPoolBalances = await Trident.Instance.getTokenBalance(tokens, pool.address, false);
  const oldManagerBalances = await Trident.Instance.getTokenBalance(tokens, manager.address, false);
  const oldLiquidity = await pool.liquidity();
  const oldTotalSupply = await manager.totalSupply();
  const liquidityDecrease = oldPriceLower.lt(oldCurrentPrice) && oldCurrentPrice.lt(oldPriceUpper) ? liquidityAmount : ZERO;
  const { dy, dx } = getAmountForLiquidity(oldPriceLower, oldCurrentPrice, oldPriceUpper, liquidityAmount);
  const [oldLowerPreviousTick, oldLowerNextTick, oldLowerLiquidity] = await pool.ticks(oldLower);
  const [oldLowerSecondPreviousTick, oldLowerSecondNextTick, oldLowerSecondLiquidity] = await pool.ticks(oldLowerNextTick);
  const [oldUpperPreviousTick, oldUpperNextTick, oldUpperLiquidity] = await pool.ticks(oldUpper);
  const [oldUpperSecondPreviousTick, oldUpperSecondNextTick, oldUpperSecondLiquidity] = await pool.ticks(oldUpperPreviousTick);
  const oldPositionState = await pool.positions(manager.address, oldLower, oldUpper);
  const oldUserNFTBalance = await manager.balanceOf(oldOwner);
  const oldZeroAddressBalance = await manager.balanceOf(ADDRESS_ZERO);

  const position = await manager.positions(tokenId);
  const { feeGrowthInside0, feeGrowthInside1 } = await pool.rangeFeeGrowth(position.lower, position.upper);
  const poolPositionLiquidity = (await pool.positions(manager.address, position.lower, position.upper)).liquidity;
  const fees0 = feeGrowthInside0.sub(position.feeGrowthInside0).mul(position.liquidity).div(TWO_POW_128);
  const fees1 = feeGrowthInside1.sub(position.feeGrowthInside1).mul(position.liquidity).div(TWO_POW_128);

  await manager.decreaseLiquidity(tokenId, liquidityAmount, recipient, unwrapBento);

  const newOwner = await manager.ownerOf(tokenId);
  const [newPoolAddress, newUserLiquidity, newLower, newUpper, newFeeGrowthInside0, newFeeGrowthInside1] = await manager.positions(tokenId);
  const [newCurrentPrice, newPriceLower, newPriceUpper] = await getPrices(pool, [newLower, newUpper]);
  const newUserBalances = await Trident.Instance.getTokenBalance(tokens, recipient, unwrapBento);
  const newPoolBalances = await Trident.Instance.getTokenBalance(tokens, pool.address, false);
  const newManagerBalances = await Trident.Instance.getTokenBalance(tokens, manager.address, false);
  const newLiquidity = await pool.liquidity();
  const newTotalSupply = await manager.totalSupply();
  const [newLowerPreviousTick, newLowerNextTick, newLowerLiquidity] = await pool.ticks(newLower);
  const [newLowerSecondPreviousTick, newLowerSecondNextTick, newLowerSecondLiquidity] = await pool.ticks(newLowerNextTick);
  const [newUpperPreviousTick, newUpperNextTick, newUpperLiquidity] = await pool.ticks(newUpper);
  const [newUpperSecondPreviousTick, newUpperSecondNextTick, newUpperSecondLiquidity] = await pool.ticks(newUpperPreviousTick);
  const newPositionState = await pool.positions(manager.address, newLower, newUpper);
  const newZeroAddressBalance = await manager.balanceOf(ADDRESS_ZERO);
  const newUserNFTBalance = await manager.balanceOf(oldOwner);
  const managerBalanceChange = [newManagerBalances[0].sub(oldManagerBalances[0]), newManagerBalances[1].sub(oldManagerBalances[1])];

  if (liquidityAmount.gte(oldUserLiquidity)) {
    expect(newUserNFTBalance).to.be.eq(oldUserNFTBalance.sub(1));
    expect(newZeroAddressBalance).to.be.eq(oldZeroAddressBalance.add(1));
    expect(newOwner).to.be.eq(ADDRESS_ZERO);
  } else {
    expect(newUserNFTBalance).to.be.eq(oldUserNFTBalance);
    expect(newZeroAddressBalance).to.be.eq(oldZeroAddressBalance);
    expect(newOwner).to.be.eq(oldOwner);
  }
  expect(newCurrentPrice).to.be.eq(oldCurrentPrice, "price changed by mistake");
  expect(newLiquidity).to.be.eq(oldLiquidity.sub(liquidityDecrease), "Liquidity didn't update correctly");
  expect(newPositionState.liquidity.toString()).to.be.eq(
    oldPositionState.liquidity.sub(liquidityAmount).toString(),
    "didn't correctly update position's liquidity"
  );
  expect(newPositionState.feeGrowthInside0Last).to.be.eq(oldPositionState.feeGrowthInside0Last, "didn't reset position's fee0 growth");
  expect(newPositionState.feeGrowthInside1Last).to.be.eq(oldPositionState.feeGrowthInside1Last, "didn't reset position's fee1 growth");

  if (oldLowerLiquidity.gt(liquidityAmount)) {
    // Tick has more liquidity than what's being removed, it shouldn't reset
    expect(newLowerLiquidity).to.be.eq(oldLowerLiquidity.sub(liquidityAmount), "Didn't decrease lower tick liquidity by the right amount");
    expect(newLowerPreviousTick).to.be.eq(oldLowerPreviousTick, "Previous tick mistekenly updated");
    expect(newLowerNextTick).to.be.eq(oldLowerNextTick, "Previous tick mistekenly updated");
    expect(newLowerSecondPreviousTick).to.be.eq(oldLowerSecondPreviousTick, "Previous tick mistekenly updated");
    expect(newLowerSecondNextTick).to.be.eq(oldLowerSecondNextTick, "Previous tick mistekenly updated");
  } else {
    // All liquidity removed, reset tick
    expect(newLowerLiquidity).to.be.eq(ZERO, "Didn't set correct liqiuidity value on new tick");
    expect(newLowerNextTick).to.be.eq(0, "Tick not reset proper");
    expect(newLowerPreviousTick).to.be.eq(0, "Tick not reset proper");
    expect(newLowerSecondPreviousTick).to.be.eq(0, "Previous tick not updated");
  }

  if (oldUpperLiquidity.gt(liquidityAmount)) {
    // Tick has more liquidity than what's being removed, it shouldn't reset
    expect(newUpperLiquidity).to.be.eq(oldUpperLiquidity.sub(liquidityAmount), "Didn't decrease upper tick liquidity by the right amount");
    expect(newUpperNextTick).to.be.eq(oldUpperNextTick, "Next tick pointer mistekenly updated");
    expect(newUpperPreviousTick).to.be.eq(oldUpperPreviousTick, "Next tick pointer mistekenly updated");
    expect(newUpperSecondNextTick).to.be.eq(oldUpperSecondNextTick, "Next tick pointer mistekenly updated");
    expect(newUpperSecondPreviousTick).to.be.eq(oldUpperSecondPreviousTick, "Next tick pointer mistekenly updated");
  } else {
    // new tick
    expect(newUpperLiquidity).to.be.eq(ZERO, "Didn't set correct liqiuidity value on new tick");
    expect(newUpperNextTick).to.be.eq(0, "Tick not reset proper");
    expect(newUpperPreviousTick).to.be.eq(0, "Tick not reset proper");
    expect(newUpperSecondNextTick).to.be.eq(0, "Next tick pointer not updated");
  }

  expectAlmostEqual(newUserBalances[0], oldUserBalances[0].add(dx).add(fees0), "Didn't receive correct amount of token0");
  expectAlmostEqual(newUserBalances[1], oldUserBalances[1].add(dy).add(fees1), "Didn't receive correct amount of token1");
  expectAlmostEqual(
    newPoolBalances[0],
    oldPoolBalances[0].sub(dx.add(fees0).add(managerBalanceChange[0])),
    "Didn't pay correct amount of token0"
  );
  expectAlmostEqual(
    newPoolBalances[1],
    oldPoolBalances[1].sub(dy.add(fees1).add(managerBalanceChange[1])),
    "Didn't pay correct amount of token1"
  );
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
  positionId?: number;
}): Promise<{ dy: BigNumber; dx: BigNumber; tokenId: BigNumber; liquidity: BigNumber }> {
  const { pool, amount0Desired, amount1Desired, native, lowerOld, lower, upperOld, upper, positionOwner, recipient, positionId } = params;
  const [currentPrice, priceLower, priceUpper] = await getPrices(pool, [lower, upper]);
  const liquidity = getLiquidityForAmount(priceLower, currentPrice, priceUpper, amount1Desired, amount0Desired);
  const tokens = await Promise.all([(await pool.getImmutables())._token0, (await pool.getImmutables())._token1]);
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
    positionId,
  });
  await Trident.Instance.router.addLiquidityLazy(pool.address, liquidity, mintData);
  const newLiquidity = await pool.liquidity();
  const priceAndTick = await pool.getPriceAndNearestTicks();
  const newPrice = priceAndTick._price;
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
    if (positionId == 0) {
      expect(oldTotalSupply.add(1).toString()).to.be.eq(newTotalSupply.toString(), "nft wasn't minted");
    }
    const [_pool, _liquidity, _lower, _upper, _feeGrowth0, _feeGrowth1] = await Trident.Instance.concentratedPoolManager.positions(
      positionId == 0 || positionId == undefined ? oldTotalSupply : positionId || 0
    );

    const nftOwner = await Trident.Instance.concentratedPoolManager.ownerOf(
      positionId == 0 || positionId == undefined ? oldTotalSupply : positionId || 0
    );

    expect(nftOwner).to.be.eq(recipient, "owner doesn't receive the nft position");
    expect(_pool).to.be.eq(pool.address, "position isn't of the correct pool");
    expect(_lower).to.be.eq(lower, "position doesn't have the correct lower tick");
    expect(_upper).to.be.eq(upper, "position doesn't have the correct upper tick");
    expect(_liquidity).to.be.gte(liquidity, "position doens't have the minted liquidity");
    // TODO check pool reserve change is correct!
    // TODO add function to calculate range fee growth here and ensure that positionManager saved the correct value
  }
  return { dy, dx, tokenId: oldTotalSupply.gt(positionId || 0) ? oldTotalSupply : BigNumber.from(positionId), liquidity };
}

export async function _addLiquidityViaRouter(params: {
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
  positionId?: number;
}) {
  const { pool, amount0Desired, amount1Desired, native, lowerOld, lower, upperOld, upper, positionOwner, recipient, positionId } = params;
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
    positionId,
  });
  await Trident.Instance.router.addLiquidityLazy(pool.address, BigNumber.from(0), mintData);
}

// use solidity here for convenience
export async function getPrices(pool: ConcentratedLiquidityPool, ticks: Array<BigNumber | number>) {
  const trident: Trident = Trident.Instance;
  const price = (await pool.getPriceAndNearestTicks())._price;
  const tickPrices = await Promise.all(ticks.map((tick) => trident.tickMath.getSqrtRatioAtTick(tick)));
  return [price, ...tickPrices];
}

export function getTickPrice(tick) {
  return Trident.Instance.tickMath.getSqrtRatioAtTick(tick);
}

export function getLiquidityForAmount(priceLower: BigNumber, currentPrice: BigNumber, priceUpper: BigNumber, dy: BigNumber, dx: BigNumber) {
  if (priceUpper.lte(currentPrice)) {
    return dy.mul("0x1000000000000000000000000").div(priceUpper.sub(priceLower));
  } else if (currentPrice.lte(priceLower)) {
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
  positionId: number | undefined;
}) {
  const { lowerOld, lower, upperOld, upper, amount0Desired, amount1Desired, native0, native1, positionOwner, recipient, positionId } =
    params;
  return ethers.utils.defaultAbiCoder.encode(
    ["int24", "int24", "int24", "int24", "uint256", "uint256", "bool", "bool", "address", "address", "uint256"],
    [lowerOld, lower, upperOld, upper, amount0Desired, amount1Desired, native0, native1, positionOwner, recipient, positionId || 0]
  );
}

export async function getPriceAtTick(tick: number) {
  return Trident.Instance.tickMath.getSqrtRatioAtTick(tick);
}

export async function getTickAtCurrentPrice(pool: ConcentratedLiquidityPool) {
  return getTickAtPrice((await pool.getPriceAndNearestTicks())._price);
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

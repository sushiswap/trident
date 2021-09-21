// @ts-nocheck

import { BigNumber } from "@ethersproject/bignumber";
import { ethers } from "hardhat";
import { Trident } from "./Trident";

export async function initialize() {
  const trident: Trident = Trident.Instance;
  await trident.init();
}

export async function addLiquidityInside() {
  const trident: Trident = Trident.Instance;
  const pool = trident.concentratedPool;
  const [token0, token1] = trident.tokens;
}

function addLiquidityViaRouter(
  token0amount: BigNumber,
  token1amount: BigNumber,
  fromBento: boolean,
  lower: BigNumber,
  lowerOld: BigNumber,
  upper: BigNumber,
  upperOld: BigNumber,
  positionOwner: string,
  positionRecipient: string
) {
  const trident: Trident = Trident.Instance;
  const pool = trident.concentratedPool;
  const currentPrice = await pool.price();
  const priceLower = await trident.tickMath.getSqrtRatioAtTick(tickLower);
  const priceUpper = await trident.tickMath.getSqrtRatioAtTick(tickUpper);
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
  trident.router.addLiquidityLazy(pool.address, mintData);
}

export function getMintData(
  lowerOld: BigNumber | number,
  lower: BigNumber | number,
  upperOld: BigNumber | number,
  upper: BigNumber | number,
  amount0Desired: BigNumber,
  amount1Desired: BigNumber,
  amount0native: bool,
  amount1native: bool,
  positionOwner: string,
  recipient: string
) {
  return ethers.utils.defaultAbiCoder.encode(
    ["int24", "int24", "int24", "int24", "uint256", "uint256", "bool", "bool", "address", "address"],
    [lowerOld, lower, upperOld, upper, amount0Desired, amount1Desired, amount0native, amount1native, positionOwner, recipient]
  );
}

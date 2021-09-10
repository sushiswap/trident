import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import * as sdk from "@sushiswap/sdk";
import { Path, ExactInputParams } from "./interfaces";
import { ethers } from "hardhat";

export const BASE_TEN = 10;
export const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

export const MAX_FEE = 10000;

// Defaults to e18 using amount * 10^18
export function getBigNumber(amount: BigNumberish, decimals = 18): BigNumber {
  return BigNumber.from(amount).mul(BigNumber.from(BASE_TEN).pow(decimals));
}

export function getIntegerRandomValue(
  exp: number,
  rnd: any
): [number, BigNumber] {
  if (exp <= 15) {
    const value = Math.floor(rnd() * Math.pow(10, exp));
    return [value, BigNumber.from(value)];
  } else {
    const random = Math.floor(rnd() * 1e15);
    const value = random * Math.pow(10, exp - 15);
    const bnValue = BigNumber.from(10)
      .pow(exp - 15)
      .mul(random);
    return [value, bnValue];
  }
}

export function getIntegerRandomValueWithMin(exp: number, min = 0, rnd: any) {
  let res;
  do {
    res = getIntegerRandomValue(exp, rnd);
  } while (res[0] < min);
  return res;
}

export function areCloseValues(v1: any, v2: any, threshold: any) {
  if (threshold == 0) return v1 == v2;
  if (v1 < 1 / threshold) return Math.abs(v1 - v2) <= 1.1;
  return Math.abs(v1 / v2 - 1) < threshold;
}

export function getExactInputParamsFromMultiRoute(
  multiRoute: sdk.MultiRoute,
  senderAddress: string
): ExactInputParams {
  const routeLegs = multiRoute.legs.length;

  let paths: Path[] = [
    {
      pool: multiRoute.legs[0].address,
      data: ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [multiRoute.legs[0].token.address, multiRoute.legs[1].address, false]
      ),
    },
    {
      pool: multiRoute.legs[1].address,
      data: ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [multiRoute.legs[1].token.address, senderAddress, false]
      ),
    },
  ];

  let inputParams: ExactInputParams = {
    amountIn: getBigNumber(multiRoute.amountIn.toString()),
    tokenIn: multiRoute.legs[0].token.address,
    tokenOut: multiRoute.legs[routeLegs - 1].token.address,
    amountOutMinimum: getBigNumber(0),
    path: paths,
  };

  return inputParams;
}

export * from "./interfaces";

export * from "./time";

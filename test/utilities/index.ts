import { BigNumber, BigNumberish } from "@ethersproject/bignumber";

export const BASE_TEN = 10;
export const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

// Defaults to e18 using amount * 10^18
export function getBigNumber(amount: BigNumberish, decimals = 18): BigNumber {
  return BigNumber.from(amount).mul(BigNumber.from(BASE_TEN).pow(decimals));
}

export * from "./time";

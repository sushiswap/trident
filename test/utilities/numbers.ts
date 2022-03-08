import { BigNumber, BigNumberish } from "ethers";

export const ZERO = BigNumber.from(0);
export const ONE = BigNumber.from(1);
export const TWO = BigNumber.from(2);

export const E18 = BigNumber.from(10).pow(18);

export const MAX_FEE = BigNumber.from(10000);

export const BASE_TEN = 10;

export function getBigNumber(amount: BigNumberish, decimals = 18): BigNumber {
  return BigNumber.from(amount).mul(BigNumber.from(BASE_TEN).pow(decimals));
}

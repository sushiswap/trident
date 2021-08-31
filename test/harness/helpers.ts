import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

export const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

export function encodedAddress(account) {
  return ethers.utils.defaultAbiCoder.encode(["address"], [account.address]);
}

// Defaults to e18 using amount * 10^18
export function getBigNumber(amount: BigNumberish, decimals = 18): BigNumber {
  return BigNumber.from(amount).mul(BigNumber.from(10).pow(decimals));
}

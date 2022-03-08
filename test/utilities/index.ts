import { BigNumber } from "@ethersproject/bignumber";
import { ONE } from "@sushiswap/core-sdk";
import { expect } from "chai";
import { ethers } from "hardhat";
import type { ERC20Mock } from "../../types";

export * from "./address";
export * from "./error";
export * from "./expect";
export * from "./math";
export * from "./numbers";
export * from "./permit";
export * from "./pools";
export * from "./random";
export * from "./snapshot";
export * from "./time";

// TODO: Refactor

export function getIntegerRandomValue(exp: number, rnd: any): [number, BigNumber] {
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

export function expectAlmostEqual(actual, expected, reason = "") {
  expect(actual).to.be.within(expected.sub(ONE), expected.add(ONE), reason);
}

export function encodedAddress(account) {
  return ethers.utils.defaultAbiCoder.encode(["address"], [account.address]);
}

export function encodedSwapData(tokenIn, to, unwrapBento) {
  return ethers.utils.defaultAbiCoder.encode(["address", "address", "bool"], [tokenIn, to, unwrapBento]);
}

export function printHumanReadable(arr) {
  console.log(
    arr.map((x) => {
      let paddedX = x.toString().padStart(19, "0");
      paddedX = paddedX.substr(0, paddedX.length - 18) + "." + paddedX.substr(paddedX.length - 18) + " ";
      return paddedX;
    })
  );
}

export function getFactories(contracts: string[]) {
  return contracts.map((contract) => getFactory(contract));
}

export function getFactory(contract: string) {
  return ethers.getContractFactory(contract);
}

export function sortTokens(tokens: ERC20Mock[]) {
  return tokens.sort((a, b) => (a.address < b.address ? -1 : 1));
}

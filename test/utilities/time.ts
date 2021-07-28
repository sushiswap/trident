import { BigNumber } from "@ethersproject/bignumber";
import { BigNumberish } from "ethers";
import { ethers } from "hardhat";

export async function advanceBlock() {
  return ethers.provider.send("evm_mine", []);
}

export async function advanceBlockTo(blockNumber: number) {
  for (let i = await ethers.provider.getBlockNumber(); i < blockNumber; i++) {
    await advanceBlock();
  }
}

export async function increase(value: BigNumber) {
  await ethers.provider.send("evm_increaseTime", [value.toNumber()]);
  await advanceBlock();
}

export async function latest() {
  const block = await ethers.provider.getBlock("latest");
  return BigNumber.from(block.timestamp);
}

export async function advanceTimeAndBlock(time: BigNumber) {
  await advanceTime(time);
  await advanceBlock();
}

export async function advanceTime(time: BigNumber) {
  await ethers.provider.send("evm_increaseTime", [time]);
}

export const duration = {
  seconds: function (value: BigNumberish) {
    return BigNumber.from(value);
  },
  minutes: function (value: BigNumberish) {
    return BigNumber.from(value).mul(this.seconds("60"));
  },
  hours: function (value: BigNumberish) {
    return BigNumber.from(value).mul(this.minutes("60"));
  },
  days: function (value: BigNumberish) {
    return BigNumber.from(value).mul(this.hours("24"));
  },
  weeks: function (value: BigNumberish) {
    return BigNumber.from(value).mul(this.days("7"));
  },
  years: function (value: BigNumberish) {
    return BigNumber.from(value).mul(this.days("365"));
  },
};

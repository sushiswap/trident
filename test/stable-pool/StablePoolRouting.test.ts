import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import seedrandom from "seedrandom";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { StableSwapRPool } from "@sushiswap/tines";
import { initializedStablePool } from "../fixtures";
import { BentoBoxV1, ERC20Mock, StablePool } from "../../types";
import { closeValues } from "@sushiswap/sdk";

const testSeed = "0"; // Change it to change random generator values
const rnd = seedrandom(testSeed); // random [0, 1)

const MINIMUM_LIQUIDITY = 1000;

function getIntegerRandomValue(exp): [number, BigNumber] {
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

function getIntegerRandomValueWithMin(exp, min = 0): [number, BigNumber] {
  let res;
  do {
    res = getIntegerRandomValue(exp);
  } while (res[0] < min);
  return res;
}

interface Environment {
  poolTines: StableSwapRPool;
  pool: StablePool;
  token0: ERC20Mock;
  token1: ERC20Mock;
  bento: BentoBoxV1;
}

async function createPool(
  fee: number, // basepoins
  res0: BigNumber,
  res1: BigNumber,
  token0Decimals: number,
  token1Decimals: number
): Promise<Environment> {
  const pool = await initializedStablePool({ fee });
  const { deployer } = await ethers.getNamedSigners();

  const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
  const token0 = await ethers.getContract<ERC20Mock>(`Token0-${token0Decimals}`);
  const token1 = await ethers.getContract<ERC20Mock>(`Token1-${token1Decimals}`);
  await token0.transfer(bento.address, res0);
  await token1.transfer(bento.address, res1);

  await bento.deposit(token0.address, bento.address, pool.address, res0, 0);
  await bento.deposit(token1.address, bento.address, pool.address, res1, 0);
  const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
  await pool.mint(mintData);

  const name0 = await token0.name();
  const name1 = await token1.name();

  const poolTines = new StableSwapRPool(
    pool.address,
    { name: name0, address: token0.address },
    { name: name1, address: token1.address },
    fee / 10_000,
    res0,
    res1
  );

  return {
    pool,
    poolTines,
    token0,
    token1,
    bento,
  };
}

async function createRandomPool(fee: number, res0exp: number, res1exp?: number): Promise<Environment> {
  const res0 = getIntegerRandomValueWithMin(res0exp, MINIMUM_LIQUIDITY)[1];
  return await createPool(fee, res0, res0, 18, 18);
}

async function swapStablePool(env: Environment, swapAmount: BigNumber, direction: boolean) {
  const tokenIn = direction ? env.token0 : env.token1;
  const tokenOut = direction ? env.token1 : env.token0;

  await tokenIn.transfer(env.bento.address, swapAmount);
  await env.bento.deposit(tokenIn.address, env.bento.address, env.pool.address, swapAmount, 0);

  const user = await ethers.getNamedSigner("alice");

  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "bool"],
    [tokenIn.address, user.address, true]
  );
  let balOutBefore: BigNumber = await tokenOut.balanceOf(user.address);
  await env.pool.swap(swapData);
  let balOutAfter: BigNumber = await tokenOut.balanceOf(user.address);
  return balOutAfter.sub(balOutBefore);
}

async function checkSwap(env: Environment, swapAmount: BigNumber, direction: boolean) {
  env.poolTines.updateReserves(
    await env.bento.balanceOf(env.token0.address, env.pool.address),
    await env.bento.balanceOf(env.token1.address, env.pool.address)
  );
  const { out: expectedAmountOut } = env.poolTines.calcOutByIn(parseInt(swapAmount.toString()), direction);
  const poolAmountOut = await swapStablePool(env, swapAmount, direction);
  expect(closeValues(parseFloat(poolAmountOut.toString()), expectedAmountOut, 1e-12)).true;
}

describe("Stable Pool <-> Tines consistency", () => {
  it("simple 6 swap test", async () => {
    const env = await createPool(30, BigNumber.from(1e6), BigNumber.from(1e6 + 1e3), 18, 18);
    await checkSwap(env, BigNumber.from(1e4), true);
    await checkSwap(env, BigNumber.from(1e5), true);
    await checkSwap(env, BigNumber.from(2e5), true);
    await checkSwap(env, BigNumber.from(1e4), false);
    await checkSwap(env, BigNumber.from(1e5), false);
    await checkSwap(env, BigNumber.from(2e5), false);
  });
});

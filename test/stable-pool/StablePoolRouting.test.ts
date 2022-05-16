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
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  feeTo: SignerWithAddress;
  bob: SignerWithAddress;

  token0: ERC20Mock;
  token1: ERC20Mock;
  bento: BentoBoxV1;
}

async function createEnvironment() {
  const deployer = await ethers.getNamedSigner("deployer");
  const alice = await ethers.getNamedSigner("alice");
  const feeTo = await ethers.getNamedSigner("barFeeTo");
  const bob = await ethers.getNamedSigner("bob");

  const pool = await initializedStablePool(); // TODO: create pool by tokens, not tokens by pool !!!
  const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
  const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
  const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

  return {
    deployer,
    alice,
    feeTo,
    bob,
    token0,
    token1,
    bento,
  };
}

async function createPool(
  env: Environment,
  fee: number, // basepoins
  res0: BigNumber,
  res1: BigNumber
): Promise<[StableSwapRPool, StablePool]> {
  const pool = await initializedStablePool({ fee });
  await env.token0.transfer(env.bento.address, res0);
  await env.token1.transfer(env.bento.address, res1);
  await env.bento.deposit(env.token0.address, env.bento.address, pool.address, res0, 0);
  await env.bento.deposit(env.token1.address, env.bento.address, pool.address, res1, 0);
  const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [env.deployer.address]);
  await pool.mint(mintData);

  const name0 = await env.token0.name();
  const name1 = await env.token1.name();

  const poolInfo = new StableSwapRPool(
    pool.address,
    { name: name0, address: env.token0.address },
    { name: name1, address: env.token1.address },
    fee / 10_000,
    res0,
    res1
  );

  return [poolInfo, pool];
}

async function createRandomPool(
  env: Environment,
  fee: number,
  res0exp: number,
  res1exp?: number
): Promise<[StableSwapRPool, StablePool]> {
  const res0 = getIntegerRandomValueWithMin(res0exp, MINIMUM_LIQUIDITY)[1];
  const res1 = res1exp == undefined ? res0 : getIntegerRandomValueWithMin(res1exp, MINIMUM_LIQUIDITY)[1];
  return createPool(env, fee, res0, res1);
}

async function swapStablePool(env: Environment, pool: StablePool, swapAmount: BigNumber, direction: boolean) {
  const tokenIn = direction ? env.token0 : env.token1;
  const tokenOut = direction ? env.token1 : env.token0;

  await tokenIn.transfer(env.bento.address, swapAmount);
  await env.bento.deposit(tokenIn.address, env.bento.address, pool.address, swapAmount, 0);
  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "bool"],
    [tokenIn.address, env.alice.address, true]
  );
  let balOutBefore: BigNumber = await tokenOut.balanceOf(env.alice.address);
  await pool.swap(swapData);
  let balOutAfter: BigNumber = await tokenOut.balanceOf(env.alice.address);
  return balOutAfter.sub(balOutBefore);
}

async function checkSwap(
  env: Environment,
  pool: StablePool,
  poolRouterInfo: StableSwapRPool,
  swapAmount: BigNumber,
  direction: boolean
) {
  poolRouterInfo.updateReserves(
    await env.bento.balanceOf(env.token0.address, pool.address),
    await env.bento.balanceOf(env.token1.address, pool.address)
  );
  const { out: expectedAmountOut } = poolRouterInfo.calcOutByIn(parseInt(swapAmount.toString()), direction);
  const poolAmountOut = await swapStablePool(env, pool, swapAmount, direction);
  //console.log(poolAmountOut.toString(), expectedAmountOut);
  expect(closeValues(parseFloat(poolAmountOut.toString()), expectedAmountOut, 1e-12)).true;
}

describe("Stable Pool <-> Tines consistency", () => {
  let env;
  before(async () => {
    env = await createEnvironment();
  });

  it("simple 6 swap test", async () => {
    const [info, pool] = await createPool(env, 30, BigNumber.from(1e6), BigNumber.from(1e6 + 1e3));
    await checkSwap(env, pool, info, BigNumber.from(1e4), true);
    await checkSwap(env, pool, info, BigNumber.from(1e5), true);
    await checkSwap(env, pool, info, BigNumber.from(2e5), true);
    await checkSwap(env, pool, info, BigNumber.from(1e4), false);
    await checkSwap(env, pool, info, BigNumber.from(1e5), false);
    await checkSwap(env, pool, info, BigNumber.from(2e5), false);
  });
});

/*describe("Check regular liquidity values", function () {
  let env;
  before(async () => {
    env = await createEnvironment();
  });
  
  for (let mintNum = 0; mintNum < 3; ++mintNum) {
    it(`Test ${mintNum + 1}`, async function () {
      const [poolRouterInfo, pool] = await createRandomPool(env, 0.003, 19, 19);

      // test regular values
      for (let swapNum = 0; swapNum < 3; ++swapNum) {
        await checkSwap(pool, poolRouterInfo, 17);
      }
      // test small values
      for (let swapNum = 0; swapNum < 3; ++swapNum) {
        await checkSwap(pool, poolRouterInfo, 2);
      }
      //test extremely big values 2^112 = 10^33.7153
      for (let swapNum = 0; swapNum < 3; ++swapNum) {
        await checkSwap(pool, poolRouterInfo, 32);
      }
    });
  }
});*/

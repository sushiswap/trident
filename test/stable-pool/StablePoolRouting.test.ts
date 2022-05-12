import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { StableSwapRPool } from "@sushiswap/tines";
import { initializedStablePool } from "../fixtures";
import { BentoBoxV1, ERC20Mock, StablePool } from "../../types";

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

async function createConstantProductPool(
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

async function swapStablePool(env: Environment, pool: StablePool, swapAmount: BigNumber) {
  await env.token0.transfer(env.bento.address, swapAmount);
  await env.bento.deposit(env.token0.address, env.bento.address, pool.address, swapAmount, 0);
  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "bool"],
    [env.token0.address, env.alice.address, true]
  );
  let balOutBefore: BigNumber = await env.token1.balanceOf(env.alice.address);
  await pool.swap(swapData);
  let balOutAfter: BigNumber = await env.token1.balanceOf(env.alice.address);
  return balOutAfter.sub(balOutBefore);
}

async function checkSwap(env: Environment, pool: StablePool, poolRouterInfo: StableSwapRPool, swapAmount: BigNumber) {
  poolRouterInfo.updateReserves(
    await env.bento.balanceOf(env.token0.address, pool.address),
    await env.bento.balanceOf(env.token1.address, pool.address)
  );
  const { out: expectedAmountOut } = poolRouterInfo.calcOutByIn(parseInt(swapAmount.toString()), true);
  const poolAmountOut = await swapStablePool(env, pool, swapAmount);
  //console.log(poolAmountOut.toString(), expectedAmountOut);
  expect(parseInt(poolAmountOut.toString())).equal(expectedAmountOut);
}

describe("Stable Pool <-> Tines consistency", () => {
  let env;
  before(async () => {
    env = await createEnvironment();
  });

  it("simple 3 swap test", async () => {
    const [info, pool] = await createConstantProductPool(env, 30, BigNumber.from(1e6), BigNumber.from(1e6 + 1e3));
    await checkSwap(env, pool, info, BigNumber.from(1e4));
    await checkSwap(env, pool, info, BigNumber.from(1e5));
    await checkSwap(env, pool, info, BigNumber.from(2e5));
  });
});

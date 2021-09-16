import { Contract } from "ethers";
import seedrandom from "seedrandom";
import { ethers } from "hardhat";
import { RHybridPool, RConstantProductPool, getBigNumber, RToken } from "@sushiswap/sdk";

import { PoolDeploymentContracts } from "./helperInterfaces";
import { MAX_HYBRID_A, MAX_LIQUIDITY, MAX_POOL_IMBALANCE, MAX_POOL_RESERVE, MIN_HYBRID_A, MIN_LIQUIDITY, MIN_POOL_IMBALANCE, MIN_POOL_RESERVE, STABLE_TOKEN_PRICE } from "./constants";
import { choice, getRandom } from "./randomHelper";

const testSeed = "7";
const rnd = seedrandom(testSeed);

export function getRandomPool(rnd: () => number, t0: RToken, t1: RToken, price: number, deploymentContracts: PoolDeploymentContracts) {
  if (price !== STABLE_TOKEN_PRICE) return getCPPool(rnd, t0, t1, price, deploymentContracts)
  if (rnd() < 0.5) getCPPool(rnd, t0, t1, price, deploymentContracts)
  return getHybridPool(rnd, t0, t1, deploymentContracts)
}

function getPoolReserve(rnd: () => number) {
  return getRandom(rnd, MIN_POOL_RESERVE, MAX_POOL_RESERVE)
}

function getPoolFee(rnd: () => number) {
  const fees = [0.003, 0.001, 0.0005]
  const cmd = choice(rnd, {
    0: 1,
    1: 1,
    2: 1
  })
  return fees[parseInt(cmd)]
}

function getPoolImbalance(rnd: () => number) {
  return getRandom(rnd, MIN_POOL_IMBALANCE, MAX_POOL_IMBALANCE)
}

function getPoolA(rnd: () => number) {
  return Math.floor(getRandom(rnd, MIN_HYBRID_A, MAX_HYBRID_A))
}

async function getCPPool(rnd: () => number, t0: RToken, t1: RToken, price: number, deploymentContracts: PoolDeploymentContracts) {
  // if (rnd() < 0.5) {
  //   const t = t0
  //   t0 = t1
  //   t1 = t
  //   price = 1 / price
  // }

  const fee = getPoolFee(rnd) * 10_000;
  const imbalance = getPoolImbalance(rnd)

  let reserve0 = getPoolReserve(rnd)
  let reserve1 = reserve0 * price * imbalance
  const maxReserve = Math.max(reserve0, reserve1)
  if (maxReserve > MAX_LIQUIDITY) {
    const reduceRate = (maxReserve / MAX_LIQUIDITY) * 1.00000001
    reserve0 /= reduceRate
    reserve1 /= reduceRate
  }
  const minReserve = Math.min(reserve0, reserve1)
  if (minReserve < MIN_LIQUIDITY) {
    const raseRate = (MIN_LIQUIDITY / minReserve) * 1.00000001
    reserve0 *= raseRate
    reserve1 *= raseRate
  }
  console.assert(reserve0 >= MIN_LIQUIDITY && reserve0 <= MAX_LIQUIDITY, 'Error reserve0 clculation')
  console.assert(reserve1 >= MIN_LIQUIDITY && reserve1 <= MAX_LIQUIDITY, 'Error reserve1 clculation ' + reserve1)

  const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256", "bool"],
      [t0.address, t1.address, fee, true]);

  const constantProductPool: Contract = await deploymentContracts.constPoolFactory.attach(
  (
    await (await deploymentContracts.masterDeployerContract.deployPool(deploymentContracts.constantPoolContract.address, deployData)).wait()
  ).events[0].args[1]);

  await deploymentContracts.bentoContract.transfer(t0.address, deploymentContracts.account.address, constantProductPool.address, getBigNumber(undefined, reserve0));
  await deploymentContracts.bentoContract.transfer(t1.address, deploymentContracts.account.address, constantProductPool.address, getBigNumber(undefined, reserve1));

  await constantProductPool.mint(ethers.utils.defaultAbiCoder.encode(["address"], [deploymentContracts.account.address]));

  return new RConstantProductPool({
    token0: t0,
    token1: t1,
    address: constantProductPool.address,
    reserve0: getBigNumber(undefined, reserve0),
    reserve1: getBigNumber(undefined, reserve1),
    fee: fee / 10_000
  })
}

async function getHybridPool(
  rnd: () => number,
  t0: RToken,
  t1: RToken,
  deploymentContracts: PoolDeploymentContracts) {
  const fee = getPoolFee(rnd) * 10_000;
  const imbalance = getPoolImbalance(rnd)
  const A = getPoolA(rnd)

  let reserve0 = getPoolReserve(rnd)
  let reserve1 = reserve0 * STABLE_TOKEN_PRICE * imbalance
  const maxReserve = Math.max(reserve0, reserve1)
  if (maxReserve > MAX_LIQUIDITY) {
    const reduceRate = (maxReserve / MAX_LIQUIDITY) * 1.00000001
    reserve0 /= reduceRate
    reserve1 /= reduceRate
  }
  const minReserve = Math.min(reserve0, reserve1)
  if (minReserve < MIN_LIQUIDITY) {
    const raseRate = (MIN_LIQUIDITY / minReserve) * 1.00000001
    reserve0 *= raseRate
    reserve1 *= raseRate
  }
  console.assert(reserve0 >= MIN_LIQUIDITY && reserve0 <= MAX_LIQUIDITY, 'Error reserve0 clculation')
  console.assert(reserve1 >= MIN_LIQUIDITY && reserve1 <= MAX_LIQUIDITY, 'Error reserve1 clculation ' + reserve1)


  const deployData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "uint256", "uint256"],
    [t0.address, t1.address, fee, A]);

  const hybridPool: Contract = await deploymentContracts.hybridPoolFactory.attach(
    (
      await (await deploymentContracts.masterDeployerContract.deployPool(deploymentContracts.hybridPoolContract.address, deployData)).wait()
    ).events[0].args[1]
  );

    await deploymentContracts.bentoContract.transfer(t0.address, deploymentContracts.account.address, hybridPool.address, getBigNumber(undefined, reserve0));
    await deploymentContracts.bentoContract.transfer(t1.address, deploymentContracts.account.address, hybridPool.address, getBigNumber(undefined, reserve1));

    await hybridPool.mint(ethers.utils.defaultAbiCoder.encode(["address"], [deploymentContracts.account.address]));

  return new RHybridPool({
    token0: t0,
    token1: t1,
    address: hybridPool.address,
    reserve0: getBigNumber(undefined, reserve0),
    reserve1: getBigNumber(undefined, reserve1),
    fee: fee / 10_000,
    A: A
  })
}
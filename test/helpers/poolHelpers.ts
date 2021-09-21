import { Contract } from "ethers";
import { ethers } from "hardhat";
import { RHybridPool, RConstantProductPool, getBigNumber, RToken } from "@sushiswap/sdk";

import { PoolDeploymentContracts } from "./helperInterfaces";
import { choice } from "./randomHelper";
 
export async function getCPPool(t0: RToken, t1: RToken, price: number, deploymentContracts: PoolDeploymentContracts, rnd: () => number) {

  const fee = getPoolFee(rnd) * 10_000;  
  const reserve1 = 1e19;
  const reserve0 = 1e19 * price; 

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

export async function getHybridPool(t0: RToken, t1: RToken, price: number, deploymentContracts: PoolDeploymentContracts, rnd: () => number) {

  const fee = getPoolFee(rnd) * 10_000;
  const A = 7000;  
  const reserve1 = 1e19;
  const reserve0 = 1e19 * price; 
 
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

function getPoolFee(rnd: () => number) {
  const fees = [0.003, 0.001, 0.0005]
  const cmd = choice(rnd, {
    0: 1,
    1: 1,
    2: 1
  })
  return fees[parseInt(cmd)]
}
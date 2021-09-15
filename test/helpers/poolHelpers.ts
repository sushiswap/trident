import { Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import seedrandom from "seedrandom";
import { ethers } from "hardhat";
import { RHybridPool, RConstantProductPool } from "@sushiswap/sdk";

import { Topology, HPoolParams, CPoolParams } from "./helperInterfaces"; 
import { getIntegerRandomValueWithMin } from "../utilities";

const testSeed = "7";
const rnd = seedrandom(testSeed);

/**
 * This function will generate paramas needed to create pools
 * @param tokens Input tokens to be used to create pool generation params
 * @returns
 */
export function generatePoolParams(tokens: Contract[]): [HPoolParams[], CPoolParams[]] {
  let hPoolParamsList: HPoolParams[] = [];
  let cPoolParamsList: CPoolParams[] = [];
  const poolCount = tokens.length - 1;

  for (let poolIndex = 0; poolIndex < poolCount; poolIndex++) {
    const tokenA = tokens[poolIndex];
    const tokenB = tokens[poolIndex + 1];

    if (poolIndex % 2 == 0) {
      const hybridParams: HPoolParams = {
        A: 6000,
        fee: 0.003,
        reserveAExponent: 19,
        reserveBExponent: 19,
        minLiquidity: 1000,
        TokenA: tokenA,
        TokenB: tokenB,
      };

      hPoolParamsList.push(hybridParams);
    } else {
      const cpParams: CPoolParams = {
        fee: 0.003,
        reserveAExponent: 33,
        reserveBExponent: 33,
        minLiquidity: 1000,
        TokenA: tokenA,
        TokenB: tokenB,
      };

      cPoolParamsList.push(cpParams);
    }
  }

  return [hPoolParamsList, cPoolParamsList];
}

/**
 * This method will generate & deploy hybrid pools using the params specified
 * @param hPoolParams 
 * @param HybridPoolFactory 
 * @param hybridPoolContract 
 * @param masterDeployerContract 
 * @param bentoContract 
 * @param account 
 * @returns 
 */
export async function generateHybridPoolsFromParams(
  hPoolParams: HPoolParams[],
  HybridPoolFactory: ContractFactory,
  hybridPoolContract: Contract,
  masterDeployerContract: Contract,
  bentoContract: Contract,
  account: SignerWithAddress
): Promise<RHybridPool[]> {
  let hybridPoolList: RHybridPool[] = [];

  for (let index = 0; index < hPoolParams.length; index++) {
    const params = hPoolParams[index];
    const A = params.A;

    const [, reserveABN] = getIntegerRandomValueWithMin(params.reserveAExponent, params.minLiquidity, rnd);
    const [, reserveBBN] = getIntegerRandomValueWithMin(params.reserveBExponent, params.minLiquidity, rnd);

    const fee = Math.round(params.fee * 10_000);

    const deployData = ethers.utils.defaultAbiCoder.encode(["address", "address", "uint256", "uint256"], [params.TokenA.address, params.TokenB.address, fee, params.A]);

    const hybridPool: Contract = await HybridPoolFactory.attach(
      (
        await (await masterDeployerContract.deployPool(hybridPoolContract.address, deployData)).wait()
      ).events[0].args[1]
    );

    await bentoContract.transfer(params.TokenA.address, account.address, hybridPool.address, reserveABN );
    await bentoContract.transfer(params.TokenB.address, account.address, hybridPool.address, reserveBBN);

    await hybridPool.mint(ethers.utils.defaultAbiCoder.encode(["address"], [account.address]));

    const hybridPoolInfo = new RHybridPool({
      A,
      reserve0: reserveABN,
      reserve1: reserveBBN,
      address: hybridPool.address,
      token0: { address: params.TokenA.address, name: params.TokenA.address },
      token1: { address: params.TokenB.address, name: params.TokenB.address },
      fee: fee,
    });

    hybridPoolList.push(hybridPoolInfo);
  }

  return hybridPoolList;
}

/**
 * This function will generate and deploy collection of constant product pools using the params specified
 * @param cPoolParams 
 * @param constPoolFactory 
 * @param constantPoolContract 
 * @param masterDeployerContract 
 * @param bentoContract 
 * @param account 
 * @returns 
 */
export async function generateConstantPoolsFromParams(
    cPoolParams: CPoolParams[], 
    constPoolFactory: ContractFactory, 
    constantPoolContract: Contract, 
    masterDeployerContract: Contract, 
    bentoContract: Contract, 
    account: SignerWithAddress): Promise<RConstantProductPool[]> {

    let constantPoolList: RConstantProductPool[] = [];

    for (let index = 0; index < cPoolParams.length; index++) {
        const params = cPoolParams[index];

        const [, reserveABN] = getIntegerRandomValueWithMin(params.reserveAExponent, params.minLiquidity, rnd);
        const [, reserveBBN] = getIntegerRandomValueWithMin(params.reserveBExponent, params.minLiquidity, rnd);
        
        const fee = Math.round(params.fee * 10_000);

        const deployData = ethers.utils.defaultAbiCoder.encode(["address", "address", "uint256", "bool"], [params.TokenA.address, params.TokenB.address, fee, true]);

        const constantProductPool: Contract = await constPoolFactory.attach(
        (
          await (await masterDeployerContract.deployPool(constantPoolContract.address, deployData)).wait()
        ).events[0].args[1]); 
        
        await bentoContract.transfer(params.TokenA.address, account.address, constantProductPool.address, reserveABN);
        await bentoContract.transfer(params.TokenB.address, account.address, constantProductPool.address, reserveBBN);
        
        await constantProductPool.mint(ethers.utils.defaultAbiCoder.encode(["address"], [account.address]));
        
        const cpPoolInfo: RConstantProductPool = new RConstantProductPool({
            reserve0: reserveABN,
            reserve1: reserveBBN,
            address: constantProductPool.address,
            token0: { address: params.TokenA.address, name: params.TokenA.address },
            token1: { address: params.TokenB.address, name: params.TokenB.address },
            fee: fee,
        });

        constantPoolList.push(cpPoolInfo);
        
    }

    return constantPoolList;
}
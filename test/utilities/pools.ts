import { BigNumber, Contract, ContractFactory } from "ethers";
import * as sdk from "@sushiswap/sdk";
import { getIntegerRandomValueWithMin } from ".";
import seedrandom from "seedrandom";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";

const testSeed = "7";
const rnd = seedrandom(testSeed);

export async function createHybridPool(
  tokenA: Contract,
  tokenB: Contract,
  swapFee: number,
  A: number,
  minLiquidity: number,
  reservesExponents: number[],
  PoolFactory: ContractFactory,
  masterDeployer: Contract,
  tridentPoolFactory: Contract,
  bento: Contract,
  alice: SignerWithAddress
): Promise<[Contract, sdk.HybridPool]> {
  const [t0, t1]: Contract[] =
    tokenA.address.toUpperCase() < tokenB.address.toUpperCase()
      ? [tokenA, tokenB]
      : [tokenB, tokenA];
  const [reserve0, reserve0BN] = getIntegerRandomValueWithMin(
    reservesExponents[0],
    minLiquidity,
    rnd
  );
  const [reserve1, reserve1BN] = getIntegerRandomValueWithMin(
    reservesExponents[1],
    minLiquidity,
    rnd
  );

  const fee = Math.round(swapFee * 10_000);
  const deployData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "uint256", "uint256"],
    [t0.address, t1.address, fee, A]
  );

  const hybridPool: Contract = await PoolFactory.attach(
    (
      await (
        await masterDeployer.deployPool(tridentPoolFactory.address, deployData)
      ).wait()
    ).events[0].args[1]
  );

  await bento.transfer(
    t0.address,
    alice.address,
    hybridPool.address,
    reserve0BN
  );
  await bento.transfer(
    t1.address,
    alice.address,
    hybridPool.address,
    reserve1BN
  );

  await hybridPool.mint(
    ethers.utils.defaultAbiCoder.encode(["address"], [alice.address])
  );

  const hybridPoolInfo = new sdk.HybridPool({
    A,
    reserve0,
    reserve1,
    address: hybridPool.address,
    token0: { address: t0.address, name: "ERC20" },
    token1: { address: t1.address, name: "ERC20" },
    fee: fee,
  });

  return [hybridPool, hybridPoolInfo];
}

export async function createConstantProductPool(
  tokenA: Contract,
  tokenB: Contract,
  swapFee: number,
  minLiquidity: number,
  reservesExponents: number[],
  PoolFactory: ContractFactory,
  masterDeployer: Contract,
  tridentPoolFactory: Contract,
  bento: Contract,
  alice: SignerWithAddress
): Promise<[Contract, sdk.ConstantProductPool]> {
  const [t0, t1]: Contract[] =
    tokenA.address.toUpperCase() < tokenB.address.toUpperCase()
      ? [tokenA, tokenB]
      : [tokenB, tokenA];
  const [reserve0, reserve0BN] = getIntegerRandomValueWithMin(
    reservesExponents[0],
    minLiquidity,
    rnd
  );
  const [reserve1, reserve1BN] = getIntegerRandomValueWithMin(
    reservesExponents[1],
    minLiquidity,
    rnd
  );

  const fee = Math.round(swapFee * 10_000);
  const deployData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "uint256", "bool"],
    [t0.address, t1.address, fee, true]
  );

  const constantProductPool: Contract = await PoolFactory.attach(
    (
      await (
        await masterDeployer.deployPool(tridentPoolFactory.address, deployData)
      ).wait()
    ).events[0].args[1]
  );

  await bento.transfer(
    t0.address,
    alice.address,
    constantProductPool.address,
    reserve0BN
  );
  await bento.transfer(
    t1.address,
    alice.address,
    constantProductPool.address,
    reserve1BN
  );

  await constantProductPool.mint(
    ethers.utils.defaultAbiCoder.encode(["address"], [alice.address])
  );

  const cpPoolInfo: sdk.ConstantProductPool = new sdk.ConstantProductPool({
    reserve0: reserve0BN,
    reserve1: reserve1BN,
    address: constantProductPool.address,
    token0: { address: t0.address, name: "ERC20" },
    token1: { address: t1.address, name: "ERC20" },
    fee,
  });

  return [constantProductPool, cpPoolInfo];
}

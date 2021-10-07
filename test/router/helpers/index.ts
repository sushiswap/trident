import { ethers } from "hardhat";
import { getBigNumber,RToken, MultiRoute, findMultiRouting, RPool, ConstantProductRPool, HybridRPool, }  from "@sushiswap/tines"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { BigNumber, Contract, ContractFactory } from "ethers";

import { Topology, PoolDeploymentContracts, TridentRoute, } from "./interfaces";
import { getCPPool, getHybridPool, getRandomPool } from "./pool";
import { getTokenPrice } from "./price";
import { RouteType } from "./constants"; 

let alice: SignerWithAddress,
  feeTo: SignerWithAddress,
  weth: Contract,
  bento: Contract,
  masterDeployer: Contract,
  router: Contract,
  hybridPool: Contract,
  constantProductPool: Contract,
  HybridPoolFactory: ContractFactory,
  ConstPoolFactory: ContractFactory,
  HybridPoolContractFactory: ContractFactory,
  ConstantPoolContractFactory: ContractFactory,
  ERC20Factory: ContractFactory,
  poolDeployment: PoolDeploymentContracts;

const tokenSupply = getBigNumber(Math.pow(2, 110));
const hybridPoolAbi = ["function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1)"];
const constantPoolAbi = ["function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint32 _blockTimestampLast)"];

export async function init(): Promise<[SignerWithAddress, string, Contract]> {
  await createAccounts();
  await deployContracts();

  return [alice, router.address, bento];
}

export function createRoute(fromToken: RToken, toToken: RToken, baseToken: RToken, topology: Topology, amountIn: number, gasPrice: number): MultiRoute | undefined {
  const route = findMultiRouting(
    fromToken,
    toToken,
    amountIn,
    topology.pools,
    baseToken,
    gasPrice
  );
  return route;
} 

export async function executeTridentRoute(tridentRouteParams: TridentRoute, toTokenAddress: string) {

  let outputBalanceBefore: BigNumber = await bento.balanceOf(toTokenAddress, alice.address);

  try {
    switch (tridentRouteParams.routeType) {
      case RouteType.SinglePool:
        await (await router.connect(alice).exactInputSingle(tridentRouteParams)).wait();
        break;
      
      case RouteType.SinglePath:
        await (await router.connect(alice).exactInput(tridentRouteParams)).wait();
          break;
      
      case RouteType.ComplexPath:
      default:
        await (await router.connect(alice).complexPath(tridentRouteParams)).wait();
        break;
    }
  } catch (error) {
    console.error('An error occurred executing trident route');
    console.log('');
    console.log(`Route Type: ${tridentRouteParams.routeType}`);

    throw error;
  }
  
  let outputBalanceAfter: BigNumber = await bento.balanceOf(
    toTokenAddress,
    alice.address
  );

  return outputBalanceAfter.sub(outputBalanceBefore);
}

export async function refreshPools(topology: Topology){
  for (let index = 0; index < topology.pools.length; index++) {
    const pool = topology.pools[index];

    const reserve0 = topology.pools[index].reserve0.toString();
    const reserve1 = topology.pools[index].reserve1.toString();
    
    // console.log('');
    // console.log('Updating reserves')
    // console.log(`Reserve 0 before update: ${reserve0}`);
    // console.log(`Reserve 1 before update: ${reserve1}`);

    if (pool instanceof ConstantProductRPool){
      const poolContract = new Contract(pool.address, constantPoolAbi, alice);
      const [reserve0, reserve1] = await poolContract.getReserves(); 
      (pool as ConstantProductRPool).updateReserves(reserve0, reserve1)
    }
    else if (pool instanceof HybridRPool) {
      const poolContract = new Contract(pool.address, hybridPoolAbi, alice);
      const [reserve0, reserve1] = await poolContract.getReserves(); 
      (pool as HybridRPool).updateReserves(reserve0, reserve1)
    }

    const reserve0After = topology.pools[index].reserve0.toString();
    const reserve1After = topology.pools[index].reserve1.toString();

    // console.log(`Reserve 0 after update: ${reserve0After}`);
    // console.log(`Reserve 1 after update: ${reserve1After}`);
    
  }
}

export async function getRandomPools(tokenCount: number, variants: number, rnd: () => number): Promise<Topology> { 
  return await getTopoplogy(tokenCount, variants, rnd); 
} 

export async function getSinglePool(rnd: () => number): Promise<Topology> {
  return await getTopoplogy(2, 1, rnd);
}

export async function getTwoSerialPools(rnd: () => number): Promise<Topology> {
  return await getTopoplogy(3, 1, rnd);
}

export async function getThreeSerialPools(rnd: () => number): Promise<Topology> {
  return await getTopoplogy(4, 1, rnd);
}

export async function getTwoParallelPools(rnd: () => number): Promise<Topology> {
  return await getTopoplogy(2, 2, rnd);
}

export async function getThreeParallelPools(rnd: () => number): Promise<Topology> {
  return await getTopoplogy(2, 3, rnd);
}
 
export async function getFivePoolBridge(rnd: () => number): Promise<Topology> { 

  let topology: Topology = {
    tokens: [],
    prices: [],
    pools: [],
  }; 

  let prices: number[] = [];
  let tokens: RToken[] = [];
  let tokenContracts: Contract[] = []; 

  for (var i = 0; i < 5; ++i) {
    tokens.push({ name: `Token${i}`, address: "" + i });
    prices.push(1);
  }

  for (let i = 0; i < tokens.length; i++) {
    const tokenContract = await ERC20Factory.deploy(tokens[0].name, tokens[0].name, tokenSupply);
    await tokenContract.deployed();
    tokenContracts.push(tokenContract);
    tokens[i].address = tokenContract.address;
  }

  await approveAndFund(tokenContracts);

  const testPool0_1 = await getCPPool(tokens[0], tokens[1], prices[1]/prices[0], poolDeployment, rnd,  1_500_0);
  const testPool0_2 = await getCPPool(tokens[0], tokens[2], prices[2]/prices[0], poolDeployment, rnd,  1_000_0);
  const testPool1_2 = await getCPPool(tokens[1], tokens[2], prices[2]/prices[1], poolDeployment, rnd,  1_000_000_000);
  const testPool1_3 = await getCPPool(tokens[1], tokens[3], prices[3]/prices[1], poolDeployment, rnd,  1_000_0);
  const testPool2_3 = await getCPPool(tokens[2], tokens[3], prices[3]/prices[2], poolDeployment, rnd,  1_500_0);

  topology.pools.push(testPool0_1);
  topology.pools.push(testPool0_2);
  topology.pools.push(testPool1_2);
  topology.pools.push(testPool1_3);
  topology.pools.push(testPool2_3);

  return {
    tokens: tokens,
    prices: prices,
    pools: topology.pools
  }
}

export async function getComplexTopoplogy(rnd: () => number): Promise<Topology> {
  const tokenContracts: Contract[] = [];
  const tokenCount = 15;
  const poolVariants = 2;

  let topology: Topology = {
    tokens: [],
    prices: [],
    pools: [],
  }; 
  

  const poolCount = tokenCount - 1;

  let priceType = 0;
  for (var i = 0; i < tokenCount; ++i) {
    topology.tokens.push({ name: `Token${i}`, address: "" + i }); 
       
      if (priceType % 2 == 0) {
        topology.prices.push(1); 
      } else {
        topology.prices.push(getTokenPrice(rnd)); 
      }
      priceType ++;
  }

  for (let i = 0; i < topology.tokens.length; i++) {
    const tokenContract = await ERC20Factory.deploy(
      topology.tokens[0].name,
      topology.tokens[0].name,
      tokenSupply
    );
    await tokenContract.deployed();
    tokenContracts.push(tokenContract);
    topology.tokens[i].address = tokenContract.address;
  }

  await approveAndFund(tokenContracts);

  let poolType = 0;
  for (i = 0; i < poolCount; i++) {
    for (let j = 1; j < poolVariants; j++) { 

      const token0 = topology.tokens[i];
      const token1 = topology.tokens[j];

      if(token0 === token1){
        continue;
      }

      const price0 = topology.prices[i];
      const price1 = topology.prices[j];
      
      if (poolType % 2 == 0) {
        topology.pools.push(
          await getHybridPool(token0, token1, 1, poolDeployment, rnd)
        );
      } else {
        topology.pools.push(
          await getCPPool(token0, token1, price0 / price1, poolDeployment, rnd)
        );
      }
      
      poolType++;
    }
  }

  return topology;
}

async function getTopoplogy(tokenCount: number, poolVariants: number, rnd: () => number): Promise<Topology> {
  const tokenContracts: Contract[] = [];

  let topology: Topology = {
    tokens: [],
    prices: [],
    pools: [],
  }; 

  const poolCount = tokenCount - 1;

  for (var i = 0; i < tokenCount; ++i) {
    topology.tokens.push({ name: `Token${i}`, address: "" + i });
    topology.prices.push(getTokenPrice(rnd));
  }

  for (let i = 0; i < topology.tokens.length; i++) {
    const tokenContract = await ERC20Factory.deploy(
      topology.tokens[0].name,
      topology.tokens[0].name,
      tokenSupply
    );
    await tokenContract.deployed();
    tokenContracts.push(tokenContract);
    topology.tokens[i].address = tokenContract.address;
  }

  await approveAndFund(tokenContracts);

  let poolType = 0;
  for (i = 0; i < poolCount; i++) {
    for (let index = 0; index < poolVariants; index++) {
      const j = i + 1;

      const token0 = topology.tokens[i];
      const token1 = topology.tokens[j];

      const price0 = topology.prices[i];
      const price1 = topology.prices[j];

      if (poolType % 2 == 0) {
        topology.pools.push(
          await getHybridPool(token0, token1, price0 / price1, poolDeployment, rnd)
        );
      } else {
        topology.pools.push(
          await getCPPool(token0, token1, price0 / price1, poolDeployment, rnd)
        );
      }

      poolType++;
    }
  }

  return topology;
}

async function createAccounts() {
  [alice, feeTo] = await ethers.getSigners();
}

async function deployContracts() {
  ERC20Factory = await ethers.getContractFactory("ERC20Mock");
  const BentoFactory = await ethers.getContractFactory("BentoBoxV1");
  const MasterDeployerFactory = await ethers.getContractFactory(
    "MasterDeployer"
  );
  const TridentRouterFactory = await ethers.getContractFactory("TridentRouter");

  HybridPoolFactory = await ethers.getContractFactory("HybridPoolFactory");
  ConstPoolFactory = await ethers.getContractFactory(
    "ConstantProductPoolFactory"
  );
  HybridPoolContractFactory = await ethers.getContractFactory("HybridPool");
  ConstantPoolContractFactory = await ethers.getContractFactory(
    "ConstantProductPool"
  );

  weth = await ERC20Factory.deploy("WETH", "WETH", tokenSupply);
  await weth.deployed();

  bento = await BentoFactory.deploy(weth.address);
  await bento.deployed();

  masterDeployer = await MasterDeployerFactory.deploy(
    17,
    feeTo.address,
    bento.address
  );
  await masterDeployer.deployed();

  hybridPool = await HybridPoolFactory.deploy(masterDeployer.address);
  await hybridPool.deployed();

  constantProductPool = await ConstPoolFactory.deploy(masterDeployer.address);
  await constantProductPool.deployed();

  await masterDeployer.addToWhitelist(hybridPool.address);
  await masterDeployer.addToWhitelist(constantProductPool.address);

  router = await TridentRouterFactory.deploy(bento.address, masterDeployer.address, weth.address);
  await router.deployed();

  await bento.whitelistMasterContract(router.address, true);

  await bento.setMasterContractApproval(
    alice.address,
    router.address,
    true,
    0,
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  );

  poolDeployment = {
    hybridPoolFactory: HybridPoolContractFactory,
    hybridPoolContract: hybridPool,
    constPoolFactory: ConstantPoolContractFactory,
    constantPoolContract: constantProductPool,
    masterDeployerContract: masterDeployer,
    bentoContract: bento,
    account: alice,
  };
}

async function approveAndFund(contracts: Contract[]) {
  for (let index = 0; index < contracts.length; index++) {
    const tokenContract = contracts[index];

    await tokenContract.approve(bento.address, tokenSupply);
    
    await bento.deposit(tokenContract.address, alice.address, alice.address, tokenSupply, 0);
  }
} 

export * from './routerParams'; 
export * from './random';
export * from './interfaces';
export * from './constants';
import { ethers } from "hardhat";
import { getBigNumber, RToken, MultiRoute, findMultiRouting } from "@sushiswap/sdk";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Contract, ContractFactory } from "ethers";
import seedrandom from 'seedrandom'

import { Topology, PoolDeploymentContracts, InitialPath, PercentagePath, Output, ComplexPathParams } from "./helperInterfaces";
import { getRandomPool } from "./poolHelpers";
import { getTokenPrice } from "./priceHelper";
import { STABLE_TOKEN_PRICE } from "./constants";

const testSeed = '2'; // Change it to change random generator values
const rnd: () => number = seedrandom(testSeed); // random [0, 1)


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
  ERC20Factory: ContractFactory;

const tokenSupply = getBigNumber(undefined, Math.pow(10, 37));
  
export async function init() {
  await createAccounts();
  await deployContracts();
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

  // deploy bento
  bento = await BentoFactory.deploy(weth.address);
  await bento.deployed();

  masterDeployer = await MasterDeployerFactory.deploy(
    17,
    feeTo.address,
    bento.address
  );
  await masterDeployer.deployed();

  // deploy hybrid pool
  hybridPool = await HybridPoolFactory.deploy(masterDeployer.address);
  await hybridPool.deployed();

  // deploy constant product pool
  constantProductPool = await ConstPoolFactory.deploy(masterDeployer.address);
  await constantProductPool.deployed();

  // whitelist the pools to master deployer
  await masterDeployer.addToWhitelist(hybridPool.address);
  await masterDeployer.addToWhitelist(constantProductPool.address);

  // deploy the router
  router = await TridentRouterFactory.deploy(bento.address, weth.address);
  await router.deployed();

  // whitelist router to bento
  await bento.whitelistMasterContract(router.address, true);

  await bento.setMasterContractApproval(
    alice.address,
    router.address,
    true,
    0,
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  );
} 

async function approveAndFund(contracts: Contract[]){
  for (let index = 0; index < contracts.length; index++) {
    const tokenContract = contracts[index];

    await tokenContract.approve(bento.address, tokenSupply);
    await bento.deposit(tokenContract.address, alice.address, alice.address, tokenSupply, 0); 
  }
} 

/**
 * Generates topology using specified tokens. 
 * @param tokens Token to be included in the topology. Must be more than one token
 * @returns 
 */
export async function getTopoplogy(rnd: () => number, tokenNumber: number): Promise<Topology> {
  
  let topology: Topology = {
    tokens: [], 
    prices: [],
    pools: [],
    tokenContracts: []
  };

  const poolDeployment: PoolDeploymentContracts = {
    hybridPoolFactory: HybridPoolContractFactory,
    hybridPoolContract: hybridPool,
    constPoolFactory: ConstantPoolContractFactory, 
    constantPoolContract: constantProductPool, 
    masterDeployerContract: masterDeployer,
    bentoContract: bento,
    account: alice
  };

  //Create tokens
  for (var i = 0; i < tokenNumber; ++i) {
    topology.tokens.push({ name: 'Token' + i, address: '' + i })
    if (i <= tokenNumber * 0.3) topology.prices.push(STABLE_TOKEN_PRICE)
    else topology.prices.push(getTokenPrice(rnd))
  }

  //Deploy tokens 
  for (let i = 0; i < topology.tokens.length; i++) {
    const tokenContract = await ERC20Factory.deploy(topology.tokens[0].name, topology.tokens[0].name , tokenSupply);
    await tokenContract.deployed();
    topology.tokenContracts.push(tokenContract);
    topology.tokens[i].address = tokenContract.address;
  }

  await approveAndFund(topology.tokenContracts);

  //Create pools
  for (i = 0; i <= tokenNumber; ++i) {
    for (var j = i + 1; j < tokenNumber; ++j) {
      topology.pools.push(await getRandomPool(rnd, topology.tokens[i], topology.tokens[j], topology.prices[i] / topology.prices[j], poolDeployment))
    }
  } 

  return topology;
}


export function getRouteFromTopology(fromToken: RToken, toToken: RToken, baseToken: RToken, topology: Topology, amountIn: number, gasPrice: number): MultiRoute {
  
  topology.pools[0].token1 = topology.pools[1].token0;
  
  const route = findMultiRouting(fromToken, toToken, amountIn, topology.pools, baseToken, gasPrice);

  return route;
}

export function convertRoute(multiRoute: MultiRoute, senderAddress: string) {

  // let testPaths: Path[] = [];

  // for (let legIndex = 0; legIndex < routeLegs; ++legIndex) {
  //   const path: Path = {
  //     pool: multiRoute.legs[legIndex].address,
  //     data: ethers.utils.defaultAbiCoder.encode(
  //       ["address", "address", "bool"],
  //       [multiRoute.legs[legIndex].token.address, senderAddress, true]
  //     ),
  //   };
  //   testPaths.push(path);
  // }

  let initialPaths: InitialPath[] = [
    {
      tokenIn: multiRoute.legs[0].token.address,
      pool: multiRoute.legs[0].address,
      amount: getBigNumber(undefined, multiRoute.amountIn),
      native: false,
      data: ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [multiRoute.legs[0].token.address, multiRoute.legs[1].address, false] //to address
      ),
    },
  ];

  let percentagePaths: PercentagePath[] = [
    {
      tokenIn: multiRoute.legs[1].token.address,
      pool: multiRoute.legs[1].address,
      balancePercentage: multiRoute.legs[1].swapPortion * 1_000_000,
      data: ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [multiRoute.legs[1].token.address, senderAddress, false]
      ),
    },
    {
      tokenIn: multiRoute.legs[2].token.address,
      pool: multiRoute.legs[2].address,
      balancePercentage: multiRoute.legs[2].swapPortion * 1_000_000,
      data: ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [multiRoute.legs[2].token.address, senderAddress, false]
      ),
    },
  ];

  let outputs: Output[] = [
    {
      token: multiRoute.legs[2].token.address,
      to: senderAddress,
      unwrapBento: false,
      minAmount: getBigNumber(undefined, 0),
    },
  ];

  const complexParams: ComplexPathParams = {
    initialPath: initialPaths,
    percentagePath: percentagePaths,
    output: outputs,
  };

  return complexParams;
}



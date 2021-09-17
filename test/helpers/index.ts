import { ethers } from "hardhat";
import { getBigNumber, RToken, MultiRoute, findMultiRouting } from "@sushiswap/sdk";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { BigNumber, Contract, ContractFactory } from "ethers";

import { Topology, PoolDeploymentContracts, InitialPath, PercentagePath, Output, ComplexPathParams, TestContracts } from "./helperInterfaces";
import { getRandomPool } from "./poolHelpers";
import { getTokenPrice } from "./priceHelper";
import { STABLE_TOKEN_PRICE } from "./constants";

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
  
export async function init() : Promise<SignerWithAddress> {
  await createAccounts();
  await deployContracts();

  return alice;
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
export async function getABCTopoplogy(rnd: () => number): Promise<Topology> {
  
  const tokenNames = ["USDC", "USDT", "DAI"];
  const tokenContracts: Contract[] = [];

  let topology: Topology = {
    tokens: [], 
    prices: [],
    pools: []
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

  const poolCount = tokenNames.length - 1;

  //Create tokens
  for (var i = 0; i < tokenNames.length; ++i) {
    topology.tokens.push({ name: tokenNames[i], address: '' + i })
    if (i <= tokenNames.length * 0.3) topology.prices.push(STABLE_TOKEN_PRICE)
    else topology.prices.push(getTokenPrice(rnd))
  }

  //Deploy tokens 
  for (let i = 0; i < topology.tokens.length; i++) {
    const tokenContract = await ERC20Factory.deploy(topology.tokens[0].name, topology.tokens[0].name , tokenSupply);
    await tokenContract.deployed();
    tokenContracts.push(tokenContract);
    topology.tokens[i].address = tokenContract.address;
  }

  await approveAndFund(tokenContracts);

  //Create pools
  for (i = 0; i < poolCount; i++) {
    const j = i + 1;
     
    const token0 = topology.tokens[i];
    const token1 = topology.tokens[j];

    const price0 = topology.prices[i];
    const price1 = topology.prices[j];

    topology.pools.push(await getRandomPool(rnd, token0, token1, price0 / price1, poolDeployment))
  } 

  return topology;
}


export function createRoute(fromToken: RToken, toToken: RToken, baseToken: RToken, topology: Topology, amountIn: number, gasPrice: number): MultiRoute {
  const route = findMultiRouting(fromToken, toToken, amountIn, topology.pools, baseToken, gasPrice, 100);
  return route;
}

export function convertRoute(multiRoute: MultiRoute, senderAddress: string) {

  let initialPaths: InitialPath[] = [];
  let percentagePaths: PercentagePath[] = [];
  let outputs: Output[] = [];

  const routeLegs = multiRoute.legs.length;

  for (let legIndex = 0; legIndex < routeLegs; ++legIndex) {

    if(legIndex === 0) {
      const initialPath: InitialPath = 
      {
        tokenIn: multiRoute.legs[legIndex].token.address,
        pool: multiRoute.legs[legIndex].address,
        amount: getBigNumber(undefined, multiRoute.amountIn),
        native: false,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].token.address, multiRoute.legs[legIndex + 1].address, false] //to address
        ),
      };

      initialPaths.push(initialPath);
      continue;
    }

    if(legIndex === routeLegs-1){

      //Create percent path for the final leg
      const percentagePath: PercentagePath = 
      {
        tokenIn: multiRoute.legs[legIndex].token.address,
        pool: multiRoute.legs[legIndex].address,
        balancePercentage: multiRoute.legs[legIndex].swapPortion * 1_000_000,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].token.address, senderAddress, false]
        ),
      }
      percentagePaths.push(percentagePath);


      //Create output for the final leg
      const output: Output =  
      {
        token: multiRoute.legs[legIndex].token.address,
        to: senderAddress,
        unwrapBento: false,
        minAmount: getBigNumber(undefined, 0),
      };
      outputs.push(output);
      continue;
    }

    //Create percent path for normal leg
    const percentagePath: PercentagePath = 
      {
        tokenIn: multiRoute.legs[legIndex].token.address,
        pool: multiRoute.legs[legIndex].address,
        balancePercentage: multiRoute.legs[legIndex].swapPortion * 1_000_000,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].token.address, multiRoute.legs[legIndex + 1].address, false]
        ),
      }
      percentagePaths.push(percentagePath); 
  } 

  const complexParams: ComplexPathParams = {
    initialPath: initialPaths,
    percentagePath: percentagePaths,
    output: outputs,
  };

  return complexParams;
}

export async function executeContractRouter(routerParams: ComplexPathParams, toTokenAddress: string) {
   
  let outputBalanceBefore: BigNumber = await bento.balanceOf(toTokenAddress, alice.address);
  // console.log("Output balance before", outputBalanceBefore.toString());

  await (await router.connect(alice).complexPath(routerParams)).wait();

  let outputBalanceAfter: BigNumber = await bento.balanceOf(toTokenAddress, alice.address);
  // console.log("Output balance after", outputBalanceAfter.toString());

  return outputBalanceAfter.sub(outputBalanceBefore);
}



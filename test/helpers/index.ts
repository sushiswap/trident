import { ethers } from "hardhat";
import { getBigNumber } from "@sushiswap/sdk";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Contract, ContractFactory } from "ethers";

import { Topology, HPoolParams, CPoolParams } from "./helperInterfaces";
import { generatePoolParams, generateHybridPoolsFromParams, generateConstantPoolsFromParams } from "./poolHelpers";
import { getTokenPricesFromPool } from "./priceHelper";
import { ConstantProductPoolFactory } from "../../types";

let alice: SignerWithAddress,
  feeTo: SignerWithAddress,
  usdt: Contract,
  usdc: Contract,
  dai: Contract,
  weth: Contract,
  bento: Contract,
  masterDeployer: Contract,
  router: Contract,
  hybridPool: Contract,
  constantProductPool: Contract,
  HybridPoolFactory: ContractFactory,
  ConstPoolFactory: ContractFactory,
  HybridPoolContractFactory: ContractFactory,
  ConstantPoolContractFactory: ContractFactory

const tokenSupply = getBigNumber(undefined, Math.pow(10, 37));
  
export async function init(): Promise<Contract[]> {
  let testTokens: Contract[]

  await createAccounts();
  await deployContracts()
  await fundAccount();
  
  testTokens = [weth, usdt, usdc, dai]

  return testTokens; 
}

async function createAccounts() {
  [alice, feeTo] = await ethers.getSigners();
}

async function deployContracts() {
  const ERC20Factory = await ethers.getContractFactory("ERC20Mock");
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

  //Deploy test tokens
  await deployTokens(ERC20Factory);

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
}

async function deployTokens(erc20ContractFactory: ContractFactory) {
  weth = await erc20ContractFactory.deploy("WETH", "WETH", tokenSupply);
  await weth.deployed();

  usdt = await erc20ContractFactory.deploy("USDT", "USDT", tokenSupply);
  await usdt.deployed();

  usdc = await erc20ContractFactory.deploy("USDC", "USDC", tokenSupply);
  await usdc.deployed();

  dai = await erc20ContractFactory.deploy("DAI", "DAI", tokenSupply);
  await dai.deployed();
}

async function fundAccount() {
  await usdc.approve(bento.address, tokenSupply);
  await usdt.approve(bento.address, tokenSupply);
  await dai.approve(bento.address, tokenSupply);

  await bento.deposit(
    usdc.address,
    alice.address,
    alice.address,
    tokenSupply,
    0
  );
  await bento.deposit(
    usdt.address,
    alice.address,
    alice.address,
    tokenSupply,
    0
  );
  await bento.deposit(
    dai.address,
    alice.address,
    alice.address,
    tokenSupply,
    0
  );

  await bento.setMasterContractApproval(
    alice.address,
    router.address,
    true,
    0,
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  );
} 

/**
 * Generates topology using specified tokens. 
 * @param tokens Token to be included in the topology. Must be more than one token
 * @returns 
 */
export async function getTopoplogy(tokens: Contract[]): Promise<Topology> {
  // getXXTopology (this, that, ...) => topology: list of tokens + prices + pools with reserves
  let topology: Topology = {
    tokens: new Map<string, Contract>(), 
    prices: [],
    hybridPools: [],
    constantPools: []
  };

  if (tokens.length <= 1)
    throw new Error(
      "Input token count needs to be greater than 1 to generate topology"
    );
 
  //Generate pool params
  const [hPoolParams, cPoolParams] = generatePoolParams(tokens);

  //Generate hybrid pools
  topology.hybridPools = await generateHybridPoolsFromParams(hPoolParams, HybridPoolContractFactory, hybridPool, masterDeployer, bento, alice);

  for (let index = 0; index < topology.hybridPools.length; index++) {
    const poolPrices = getTokenPricesFromPool(topology.hybridPools[0]);
    topology.prices.concat(poolPrices);
  }

  //Generate constant pools
  topology.constantPools = await generateConstantPoolsFromParams(cPoolParams, ConstantPoolContractFactory, constantProductPool, masterDeployer, bento, alice);

  for (let index = 0; index < topology.constantPools.length; index++) {
    const poolPrices = getTokenPricesFromPool(topology.constantPools[0]);
    topology.prices.concat(poolPrices);
  }

  return topology;
}



import { ethers } from "hardhat";
import {
  getBigNumber,
  RToken,
  MultiRoute,
  findMultiRouting,
} from "@sushiswap/sdk";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { BigNumber, Contract, ContractFactory } from "ethers";

import {
  Topology,
  PoolDeploymentContracts,
  InitialPath,
  PercentagePath,
  Output,
  ComplexPathParams,
} from "./helperInterfaces";
import { getCPPool, getHybridPool } from "./poolHelpers";
import { getTokenPrice } from "./priceHelper";

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

export async function init(): Promise<SignerWithAddress> {
  await createAccounts();
  await deployContracts();

  return alice;
}

export async function getABCTopoplogy(rnd: () => number): Promise<Topology> {
  return await getTopoplogy(3, 1, rnd);
}

export async function getABCDTopoplogy(rnd: () => number): Promise<Topology> {
  return await getTopoplogy(4, 1, rnd);
}

export async function getAB2VariantTopoplogy(
  rnd: () => number
): Promise<Topology> {
  return await getTopoplogy(2, 2, rnd);
}

export async function getAB3VariantTopoplogy(
  rnd: () => number
): Promise<Topology> {
  return await getTopoplogy(2, 3, rnd);
}

export function createRoute(
  fromToken: RToken,
  toToken: RToken,
  baseToken: RToken,
  topology: Topology,
  amountIn: number,
  gasPrice: number
): MultiRoute {
  const route = findMultiRouting(
    fromToken,
    toToken,
    amountIn,
    topology.pools,
    baseToken,
    gasPrice,
    32
  );
  return route;
}

export async function executeComplexPath(
  routerParams: ComplexPathParams,
  toTokenAddress: string
) {
  let outputBalanceBefore: BigNumber = await bento.balanceOf(
    toTokenAddress,
    alice.address
  );

  await (await router.connect(alice).complexPath(routerParams)).wait();

  let outputBalanceAfter: BigNumber = await bento.balanceOf(
    toTokenAddress,
    alice.address
  );

  return outputBalanceAfter.sub(outputBalanceBefore);
}

async function getTopoplogy(
  tokenCount: number,
  poolVariants: number,
  rnd: () => number
): Promise<Topology> {
  const tokenContracts: Contract[] = [];

  let topology: Topology = {
    tokens: [],
    prices: [],
    pools: [],
  };

  const poolDeployment: PoolDeploymentContracts = {
    hybridPoolFactory: HybridPoolContractFactory,
    hybridPoolContract: hybridPool,
    constPoolFactory: ConstantPoolContractFactory,
    constantPoolContract: constantProductPool,
    masterDeployerContract: masterDeployer,
    bentoContract: bento,
    account: alice,
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
          await getHybridPool(
            token0,
            token1,
            price0 / price1,
            poolDeployment,
            rnd
          )
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

  router = await TridentRouterFactory.deploy(bento.address, weth.address);
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
}

async function approveAndFund(contracts: Contract[]) {
  for (let index = 0; index < contracts.length; index++) {
    const tokenContract = contracts[index];

    await tokenContract.approve(bento.address, tokenSupply);
    await bento.deposit(
      tokenContract.address,
      alice.address,
      alice.address,
      tokenSupply,
      0
    );
  }
}

export function getComplexPathParams(
  multiRoute: MultiRoute,
  senderAddress: string,
  fromToken: string,
  toToken: string
) {
  let initialPaths: InitialPath[] = [];
  let percentagePaths: PercentagePath[] = [];
  let outputs: Output[] = [];

  const output: Output = {
    token: toToken,
    to: senderAddress,
    unwrapBento: false,
    minAmount: getBigNumber(undefined, 0),
  };
  outputs.push(output);

  const routeLegs = multiRoute.legs.length;

  for (let legIndex = 0; legIndex < routeLegs; ++legIndex) {
    const recipentAddress = getRecipentAddress(
      multiRoute,
      legIndex,
      fromToken,
      senderAddress
    );

    if (multiRoute.legs[legIndex].token.address === fromToken) {
      const initialPath: InitialPath = {
        tokenIn: multiRoute.legs[legIndex].token.address,
        pool: multiRoute.legs[legIndex].address,
        amount: getBigNumber(
          undefined,
          multiRoute.amountIn * multiRoute.legs[legIndex].absolutePortion
        ),
        native: false,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].token.address, recipentAddress, false]
        ),
      };
      initialPaths.push(initialPath);
    } else {
      const percentagePath: PercentagePath = {
        tokenIn: multiRoute.legs[legIndex].token.address,
        pool: multiRoute.legs[legIndex].address,
        balancePercentage: multiRoute.legs[legIndex].swapPortion * 1_000_000,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].token.address, recipentAddress, false]
        ),
      };
      percentagePaths.push(percentagePath);
    }
  }

  const complexParams: ComplexPathParams = {
    initialPath: initialPaths,
    percentagePath: percentagePaths,
    output: outputs,
  };

  return complexParams;
}

function getRecipentAddress(
  multiRoute: MultiRoute,
  legIndex: number,
  fromTokenAddress: string,
  senderAddress: string
): string {
  const isLastLeg = legIndex === multiRoute.legs.length - 1;

  if (
    isLastLeg ||
    multiRoute.legs[legIndex + 1].token.address === fromTokenAddress
  ) {
    return senderAddress;
  } else {
    return multiRoute.legs[legIndex + 1].address;
  }
}

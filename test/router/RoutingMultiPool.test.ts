import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { BigNumber, Contract } from "ethers";
import { ethers } from "hardhat";
import {
  areCloseValues,
  getBigNumber,
  getIntegerRandomValue,
} from "../utilities";
import {
  createConstantProductPool,
  createHybridPool,
} from "../utilities/pools";
import * as sdk from "@sushiswap/sdk";
import seedrandom from "seedrandom";
import { ConstantProductPool } from "@sushiswap/sdk";
import { string } from "hardhat/internal/core/params/argumentTypes";
import { expect } from "chai";

const testSeed = "7";
const rnd = seedrandom(testSeed);

const ERC20DeployAmount = getBigNumber("1000000000000000000");

interface SwapParams {
  tokenIn: string;
  recipient: string;
  unwrapBento: string;
}

interface Path {
  pool: string;
  data: string;
}
interface ExactInputParams {
  tokenIn: string;
  tokenOut: string;
  amountIn: BigNumber;
  amountOutMinimum: BigNumber;
  path: Path[];
}

interface HybridPoolParams {
  A: number;
  fee: number;
  reserve0Exponent: number;
  reserve1Exponent: number;
  minLiquidity: number;
}

interface ConstProdParams {
  fee: number;
  reserve0Exponent: number;
  reserve1Exponent: number;
  minLiquidity: number;
}

describe("MultiPool Routing Tests", function () {
  let alice: SignerWithAddress,
    feeTo: SignerWithAddress,
    usdt: Contract,
    usdc: Contract,
    weth: Contract,
    bento: Contract,
    masterDeployer: Contract,
    tridentPoolFactory: Contract,
    router: Contract;

  async function MakePools(
    hybridParams: HybridPoolParams,
    cpParams: ConstProdParams
  ): Promise<
    [[Contract, sdk.HybridPool], [Contract, sdk.ConstantProductPool]]
  > {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const ConstProdFactory = await ethers.getContractFactory(
      "ConstantProductPoolFactory"
    );
    const HybridFactory = await ethers.getContractFactory("HybridPoolFactory");
    const SwapRouter = await ethers.getContractFactory("TridentRouter");
    const HybridPoolContract = await ethers.getContractFactory("HybridPool");
    const ConstantProductPoolContract = await ethers.getContractFactory(
      "ConstantProductPool"
    );

    // deploy tokens
    weth = await ERC20.deploy("WETH", "WETH", ERC20DeployAmount);
    await weth.deployed();
    usdt = await ERC20.deploy("USDT", "USDT", ERC20DeployAmount);
    await usdt.deployed();
    usdc = await ERC20.deploy("USDC", "USDC", ERC20DeployAmount);
    await usdc.deployed();

    // deploy bento
    bento = await Bento.deploy(weth.address);
    await bento.deployed();

    masterDeployer = await Deployer.deploy(17, feeTo.address, bento.address);
    await masterDeployer.deployed();

    // deploy hybrid pool
    const hybridPool = await HybridFactory.deploy(masterDeployer.address);
    await hybridPool.deployed();

    // deploy constant product pool
    const constProductPool = await ConstProdFactory.deploy(
      masterDeployer.address
    );
    await constProductPool.deployed();

    // whitelist the pools to master deployer
    await masterDeployer.addToWhitelist(hybridPool.address);
    await masterDeployer.addToWhitelist(constProductPool.address);

    // deploy the router
    router = await SwapRouter.deploy(bento.address, weth.address);
    await router.deployed();

    // whitelist router to bento
    await bento.whitelistMasterContract(router.address, true);

    await usdc.approve(bento.address, ERC20DeployAmount);
    await usdt.approve(bento.address, ERC20DeployAmount);

    await bento.deposit(
      usdc.address,
      alice.address,
      alice.address,
      ERC20DeployAmount,
      0
    );
    await bento.deposit(
      usdt.address,
      alice.address,
      alice.address,
      ERC20DeployAmount,
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

    const [hPool, hPoolInfo] = await createHybridPool(
      usdc,
      usdt,
      hybridParams.fee,
      hybridParams.A,
      hybridParams.minLiquidity,
      [hybridParams.reserve0Exponent, hybridParams.reserve1Exponent],
      HybridPoolContract,
      masterDeployer,
      hybridPool,
      bento,
      alice
    );
    const [cpPool, cpPoolInfo] = await createConstantProductPool(
      usdc,
      usdt,
      cpParams.fee,
      cpParams.minLiquidity,
      [cpParams.reserve0Exponent, cpParams.reserve1Exponent],
      ConstantProductPoolContract,
      masterDeployer,
      constProductPool,
      bento,
      alice
    );

    return [
      [hPool, hPoolInfo],
      [cpPool, cpPoolInfo],
    ];
  }

  async function checkSwaps(
    tokens: Contract[],
    swapAmountsExp: number[],
    hybridPool: Contract,
    cpPool: Contract,
    hPoolInfo: sdk.HybridPool,
    cpPoolInfo: sdk.ConstantProductPool
  ) {
    for (var swapAmountExp of swapAmountsExp) {
      for (let swapNum = 0; swapNum < 3; ++swapNum) {
        // check each swap exp 3 times
        await CheckSwap(
          tokens,
          swapAmountExp,
          hybridPool,
          cpPool,
          hPoolInfo,
          cpPoolInfo
        );
      }
    }
  }

  let swapDirection = true;
  async function CheckSwap(
    tokens: Contract[],
    swapAmountExp: number,
    hybridPool: Contract,
    cpPool: Contract,
    hybridPoolInfo: sdk.HybridPool,
    cpPoolInfo: sdk.ConstantProductPool
  ) {
    const [swapExp, swapExpBN] = getIntegerRandomValue(swapAmountExp, rnd);
    const [t0, t1]: Contract[] = swapDirection
      ? [tokens[0], tokens[1]]
      : [tokens[1], tokens[0]];

    // const poolRouterInfo = {...poolInfo };
    // poolRouterInfo.reserve0 = await bento.balanceOf(tokens[0].address, ????);
    // poolrouterInfo.reserve1 = await bento.balanceOf(tokens[1].address, ????);

    let balanceBefore: BigNumber = await bento.balanceOf(
      t1.address,
      alice.address
    );

    //  -- ROUTER PARAMS --
    let paths: Path[] = [
      {
        pool: hybridPool.address,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [t0.address, alice.address, false]
        ),
      },
      {
        pool: cpPool.address,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [t0.address, alice.address, false]
        ),
      },
    ];
    let inputParams: ExactInputParams = {
      tokenIn: t0.address,
      tokenOut: t1.address,
      amountIn: swapExpBN,
      amountOutMinimum: getBigNumber(0),
      path: paths,
    };

    // execute transaction
    const tx = await router.connect(alice).exactInput(inputParams);
    let balanceAfter: BigNumber = await bento.balanceOf(
      t1.address,
      alice.address
    );
    const amountOutPoolBN = balanceAfter.sub(balanceBefore);

    // cant do this yet cause findRouterMulti function net exposed by sdk yet?
    // const amountOutPrediction = sdk. where is find router multi??
    // expect(areCloseValues(amountOutPrediction, amountOutPoolBN)).to.equal(true, "predicted amount did not equal actual swapped amount");

    swapDirection = !swapDirection;
  }

  it("Should deploy the pools!", async function () {
    const hybridParams: HybridPoolParams = {
      A: 6000,
      fee: 0.003,
      reserve0Exponent: 19,
      reserve1Exponent: 19,
      minLiquidity: 1000,
    };

    const cpParams: ConstProdParams = {
      fee: 0.003,
      reserve0Exponent: 19,
      reserve1Exponent: 19,
      minLiquidity: 1000,
    };

    const [[hybridPool, hybridPoolInfo], [cpPool, cpPoolInfo]] =
      await MakePools(hybridParams, cpParams);

    // normal values
    await checkSwaps(
      [usdc, usdt],
      [17, 2, 23],
      hybridPool,
      cpPool,
      hybridPoolInfo,
      cpPoolInfo
    );
  });
});

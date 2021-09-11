import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { BigNumber, Contract } from "ethers";
import { ethers } from "hardhat";
import {
  areCloseValues,
  getIntegerRandomValue,
  HybridPoolParams,
  ConstantProductPoolParams,
  getExactInputParamsFromMultiRoute,
  ExactInputParams,
  getComplexPathParamsFromMultiRoute,
  ComplexPathParams,
} from "../utilities";
import {
  createConstantProductPool,
  createHybridPool,
} from "../utilities/pools";
import * as sdk from "@sushiswap/sdk";
import seedrandom from "seedrandom";
import { expect } from "chai";
import { getBigNumber } from "@sushiswap/sdk";

const testSeed = "7";
const rnd = seedrandom(testSeed);

const ERC20DeployAmount = getBigNumber(undefined, Math.pow(10, 37));
const gasPrice = 1 * 200 * 1e-9;

describe("MultiPool Routing Tests", function () {
  let alice: SignerWithAddress,
    feeTo: SignerWithAddress,
    usdt: Contract,
    usdc: Contract,
    dai: Contract,
    weth: Contract,
    bento: Contract,
    masterDeployer: Contract,
    router: Contract;

  async function MakePools(
    hybridParams: HybridPoolParams,
    cpParams: ConstantProductPoolParams
  ): Promise<
    [[Contract, sdk.RHybridPool], [Contract, sdk.RConstantProductPool]]
  > {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const SwapRouter = await ethers.getContractFactory("TridentRouter");
    const HybridFactory = await ethers.getContractFactory("HybridPoolFactory");
    const HybridPoolContract = await ethers.getContractFactory("HybridPool");
    const ConstProdFactory = await ethers.getContractFactory(
      "ConstantProductPoolFactory"
    );
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
    dai = await ERC20.deploy("DAI", "DAI", ERC20DeployAmount);

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
    await dai.approve(bento.address, ERC20DeployAmount);

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
    await bento.deposit(
      dai.address,
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

    // HybridPool has USDC <> USDT
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
    // ConstantProductPool has USDT <> DAI
    const [cpPool, cpPoolInfo] = await createConstantProductPool(
      usdt,
      dai,
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
    hPoolInfo: sdk.RHybridPool,
    cpPoolInfo: sdk.RConstantProductPool
  ) {
    for (var swapAmountExp of swapAmountsExp) {
      for (let swapNum = 0; swapNum < 1; ++swapNum) {
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
    hybridPoolInfo: sdk.RHybridPool,
    cpPoolInfo: sdk.RConstantProductPool
  ) {
    const [swapExp, swapExpBN] = getIntegerRandomValue(swapAmountExp, rnd);
    const [t0, t1]: Contract[] = swapDirection
      ? [tokens[0], tokens[1]]
      : [tokens[1], tokens[0]];

    // const poolRouterInfo = {...poolInfo };
    // poolRouterInfo.reserve0 = await bento.balanceOf(tokens[0].address, ????);
    // poolrouterInfo.res`erve1 = await bento.balanceOf(tokens[1].address, ????);

    const hybridT1Before = hybridPoolInfo.token1;

    hybridPoolInfo.token1 = cpPoolInfo.token0; //??

    // HybridPool has          t0 = USDC <> t1 = USDT
    // ConstantProductPool has t0 = USDT <> t1 = DAI
    const amountOutPrediction: sdk.MultiRoute | undefined =
      sdk.findMultiRouting(
        hybridPoolInfo.token0, // USDC
        cpPoolInfo.token1, // DAI
        swapExp,
        [hybridPoolInfo, cpPoolInfo],
        cpPoolInfo.token0, // USDT
        gasPrice,
        100
      );

    const complexParams: ComplexPathParams = getComplexPathParamsFromMultiRoute(
      amountOutPrediction,
      alice.address
    );

    let balanceBefore: BigNumber = await bento.balanceOf(
      usdc.address,
      alice.address
    );
    let outputBalanceBefore: BigNumber = await bento.balanceOf(
      dai.address,
      alice.address
    );
    let usdtBalanceBefore: BigNumber = await bento.balanceOf(
      usdt.address,
      alice.address
    );

    await router.connect(alice).complexPath(complexParams);

    let balanceAfter: BigNumber = await bento.balanceOf(
      usdc.address,
      alice.address
    );
    let outputBalanceAfter: BigNumber = await bento.balanceOf(
      dai.address,
      alice.address
    );
    let usdtBalanceAfter: BigNumber = await bento.balanceOf(
      usdt.address,
      alice.address
    );

    const amountOutPoolBN = outputBalanceAfter.sub(outputBalanceBefore);

    expect(
      areCloseValues(
        amountOutPrediction.amountOut,
        parseInt(amountOutPoolBN.toString()),
        1e-14
      )
    ).to.equal(true, "predicted amount did not equal actual swapped amount");

    swapDirection = !swapDirection;
  }

  // check normal values
  it("Should Test Normal Values", async function () {
    const hybridParams: HybridPoolParams = {
      A: 6000,
      fee: 0.003,
      reserve0Exponent: 19,
      reserve1Exponent: 19,
      minLiquidity: 1000,
    };

    const cpParams: ConstantProductPoolParams = {
      fee: 0.003,
      reserve0Exponent: 19,
      reserve1Exponent: 19,
      minLiquidity: 1000,
    };

    const [[hybridPool, hybridPoolInfo], [cpPool, cpPoolInfo]] =
      await MakePools(hybridParams, cpParams);

    // normal values
    await checkSwaps(
      [usdc, dai],
      [17],
      hybridPool,
      cpPool,
      hybridPoolInfo,
      cpPoolInfo
    );
  });

  // check big liquidity values
  /*  it("Should test big liquidty values", async function () {
    const hybridParams: HybridPoolParams = {
      A: 200_000,
      fee: 0.003,
      reserve0Exponent: 33,
      reserve1Exponent: 33,
      minLiquidity: 1000,
    };

    const cpParams: ConstantProductPoolParams = {
      fee: 0.003,
      reserve0Exponent: 33,
      reserve1Exponent: 33,
      minLiquidity: 1000,
    };

    const [[hybridPool, hybridPoolInfo], [cpPool, cpPoolInfo]] =
      await MakePools(hybridParams, cpParams);

    await checkSwaps(
      [usdc, dai],
      [17, 2, 33],
      hybridPool,
      cpPool,
      hybridPoolInfo,
      cpPoolInfo
    );
  });

  it("Should Test small liquidity values", async function () {
    const hybridParams: HybridPoolParams = {
      A: 200_000,
      fee: 0.003,
      reserve0Exponent: 4,
      reserve1Exponent: 4,
      minLiquidity: 1000,
    };

    const cpParams: ConstantProductPoolParams = {
      fee: 0.003,
      reserve0Exponent: 4,
      reserve1Exponent: 4,
      minLiquidity: 1000,
    };
    const [[hybridPool, hybridPoolInfo], [cpPool, cpPoolInfo]] =
      await MakePools(hybridParams, cpParams);

    await checkSwaps(
      [usdc, dai],
      [3, 7],
      hybridPool,
      cpPool,
      hybridPoolInfo,
      cpPoolInfo
    );
  });*/
});

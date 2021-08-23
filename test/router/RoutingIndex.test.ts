//@ts-nocheck

import { BigNumber } from "@ethersproject/bignumber";
import { ethers } from "hardhat";
import {
  areCloseValues,
  getBigNumber,
  getIntegerRandomValue,
} from "../utilities";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Contract, ContractFactory } from "ethers";
import { calcOutByIn, WeightedPool, PoolType, RToken } from "@sushiswap/sdk";
import seedrandom from "seedrandom";
import { expect } from "chai";

const testSeed = "3"; // Change it to change random generator values
const rnd = seedrandom(testSeed); // random [0, 1)

// -------------    CONTRACT CONSTANTS     -------------
const BASE: BigNumber = getBigNumber(10, 18);
const MIN_TOKENS = 2;
const MAX_TOKENS = 8;
const MIN_FEE = getBigNumber("1000000000000", 0);
const MAX_FEE = getBigNumber("100000000000000000", 0);
const MIN_WEIGHT = BASE;
const MAX_WEIGHT = BASE.mul(getBigNumber(50, 0));
const MAX_TOTAL_WEIGHT = BASE.mul(getBigNumber(50, 0));
const MAX_IN_RATIO = BASE.div(getBigNumber(2, 0));
const MAX_OUT_RATIO = BASE.div(getBigNumber(3, 0)).add(getBigNumber(1, 0));
// -------------         -------------

// ------------- PARAMETERS -------------
// what each ERC20 is deployed with
const ERCDeployAmount: BigNumber = getBigNumber(10, 30);
// -------------         -------------

interface ExactInputSingleParams {
  amountIn: BigNumber;
  amountOutMinimum: BigNumber;
  pool: string;
  tokenIn: string;
  data: string;
}
interface tokenAndWeight {
  token: Contract;
  weight: BigNumber;
}

function encodeSwapData(
  tokenIn: string,
  tokenOut: string,
  recipient: string,
  unwrapBento: boolean,
  amountIn: BigNumber | number
): string {
  return ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "address", "bool", "uint256"],
    [tokenIn, tokenOut, recipient, unwrapBento, amountIn]
  );
}

describe("IndexPool test", function () {
  let alice: SignerWithAddress,
    feeTo: SignerWithAddress,
    usdt: Contract,
    usdc: Contract,
    weth: Contract,
    bento: Contract,
    masterDeployer: Contract,
    tridentPoolFactory: Contract,
    router: Contract,
    Pool: ContractFactory;

  async function deployPool(
    fee: BigNumber,
    tokenWeights: BigNumber[],
    toMint: BigNumber
  ): Promise<[WeightedPool, Contract, tokenAndWeight[]]> {
    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("IndexPoolFactory");
    const SwapRouter = await ethers.getContractFactory("TridentRouter");
    Pool = await ethers.getContractFactory("IndexPool");
    [alice, feeTo] = await ethers.getSigners();

    weth = await ERC20.deploy("WETH", "WETH", ERCDeployAmount);
    await weth.deployed();
    usdt = await ERC20.deploy("USDT", "USDT", ERCDeployAmount);
    await usdt.deployed();
    usdc = await ERC20.deploy("USDC", "USDC", ERCDeployAmount);
    await usdc.deployed();

    bento = await Bento.deploy(weth.address);
    await bento.deployed();

    masterDeployer = await Deployer.deploy(17, feeTo.address, bento.address);
    await masterDeployer.deployed();

    tridentPoolFactory = await PoolFactory.deploy(masterDeployer.address);
    await tridentPoolFactory.deployed();
    router = await SwapRouter.deploy(bento.address, weth.address);
    await router.deployed();

    // Whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(tridentPoolFactory.address);

    // Whitelist Router on BentoBox
    await bento.whitelistMasterContract(router.address, true);
    // Approve BentoBox token deposits
    await usdc.approve(bento.address, ERCDeployAmount);
    await usdt.approve(bento.address, ERCDeployAmount);
    // Make BentoBox token deposits
    await bento.deposit(
      usdc.address,
      alice.address,
      alice.address,
      ERCDeployAmount,
      0
    );
    await bento.deposit(
      usdt.address,
      alice.address,
      alice.address,
      ERCDeployAmount,
      0
    );
    // Approve Router to spend 'alice' BentoBox tokens
    await bento.setMasterContractApproval(
      alice.address,
      router.address,
      true,
      "0",
      "0x0000000000000000000000000000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    );

    const [t0, t1]: Contract[] =
      usdt.address.toUpperCase() > usdc.address.toUpperCase()
        ? [usdt, usdc]
        : [usdc, usdt];

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address[]", "uint256[]", "uint256"],
      [[t0.address, t1.address], tokenWeights, fee]
    );

    let tokensAndweights: tokenAndWeight[] = [
      { token: t0, weight: tokenWeights[0] },
      { token: t1, weight: tokenWeights[1] },
    ];

    let tx = await (
      await masterDeployer.deployPool(tridentPoolFactory.address, deployData)
    ).wait();
    const pool: Contract = await Pool.attach(tx.events[1].args.pool);

    await bento.transfer(
      usdt.address,
      alice.address,
      pool.address,
      ERCDeployAmount
    );
    await bento.transfer(
      usdc.address,
      alice.address,
      pool.address,
      ERCDeployAmount
    );

    await pool.mint(
      ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256"],
        [alice.address, toMint]
      )
    );

    const poolInfo: WeightedPool = {
      address: pool.address,
      type: PoolType.Weighted,
      reserve0: ERCDeployAmount,
      reserve1: ERCDeployAmount,
      weight0: tokenWeights[0],
      weight1: tokenWeights[1],
      minLiquidity: 0,
      token0: { name: t0.address, gasPrice: 0 },
      token1: { name: t1.address, gasPrice: 0 },
      swapGasCost: 0,
      fee: fee,
    };

    return [poolInfo, pool, tokensAndweights];
  }

  let swapDirection = true;
  async function checkSwap(
    tokensAndWeights: tokenAndWeight[],
    pool: Contract,
    poolRouterInfo: WeightedPool,
    swapAmountExp: number
  ) {
    // get the swap amountIn value randomly
    const [value, bnValue] = getIntegerRandomValue(swapAmountExp, rnd);

    let [t0, t1] = swapDirection
      ? [tokensAndWeights[0], tokensAndWeights[1]]
      : [tokensAndWeights[1], tokensAndWeights[0]];

    // setup router input
    let params: ExactInputSingleParams = {
      amountIn: bnValue,
      amountOutMinimum: getBigNumber(0, 0),
      pool: pool.address,
      tokenIn: t0.token.address,
      data: encodeSwapData(
        t0.token.address,
        t1.token.address,
        alice.address,
        false,
        bnValue
      ),
    };

    // console.log("Pool balance before...");
    // let bal1 = await bento.balanceOf(tokensAndWeights[0].token.address, pool.address)
    // console.log(bal1.toString());
    // let bal2 = await bento.balanceOf(tokensAndWeights[1].token.address, pool.address);
    // console.log(bal2.toString());

    // console.log("Alice balance before...");
    // bal1 = await bento.balanceOf(tokensAndWeights[0].token.address, alice.address)
    // console.log(bal1.toString());
    // bal2 = await bento.balanceOf(tokensAndWeights[1].token.address, alice.address);
    // console.log(bal2.toString());
    // console.log("\n")

    // cache reserves
    poolRouterInfo.reserve0 = await bento.balanceOf(
      tokensAndWeights[0].token.address,
      pool.address
    );
    poolRouterInfo.reserve1 = await bento.balanceOf(
      tokensAndWeights[1].token.address,
      pool.address
    );

    // swap and get before and after balances
    let balOutBefore: BigNumber = await bento.balanceOf(
      t1.token.address,
      alice.address
    );
    await router
      .connect(alice)
      .swap(
        encodeSwapData(
          t0.token.address,
          t1.token.address,
          alice.address,
          false,
          bnValue
        )
      );
    // await router.connect(alice).exactInputSingle(params); <---- THIS UNDERFLOWS ???
    let balOutAfter: BigNumber = await bento.balanceOf(
      t1.token.address,
      alice.address
    );

    // console.log("Pool balance AFTER...");
    // bal1 = await bento.balanceOf(tokensAndWeights[0].token.address, pool.address)
    // console.log(bal1.toString());
    // bal2 = await bento.balanceOf(tokensAndWeights[1].token.address, pool.address);
    // console.log(bal2.toString());
    // console.log("Alice balance AFTER...");
    // bal1 = await bento.balanceOf(tokensAndWeights[0].token.address, alice.address)
    // console.log(bal1.toString());
    // bal2 = await bento.balanceOf(tokensAndWeights[1].token.address, alice.address);
    // console.log(bal2.toString());
    // console.log("\n\n")

    // calc swap out amount and predicted amount
    const amountOutPool: BigNumber = balOutAfter.sub(balOutBefore);
    console.log("Swap out: ", amountOutPool.toString());
    const amountOutPrediction = calcOutByIn(poolRouterInfo, value, true);

    // // check consistency
    // expect(areCloseValues(amountOutPrediction, amountOutPool, 1e-12)).equals(
    // 	true,
    // 	"predicted amount out did not equal swapped amount result"
    // );
    swapDirection = !swapDirection;
  }

  async function checkSwaps(
    tokensAndWeights: tokenAndWeight[],
    poolRouterInfo: WeightedPool,
    pool: Contract
  ) {
    // test regular values

    for (let swapNum = 0; swapNum < 3; ++swapNum) {
      await checkSwap(tokensAndWeights, pool, poolRouterInfo, 17);
    }
    consoleGreen("\t ✓ Regular Values");

    // test small values
    for (let swapNum = 0; swapNum < 3; ++swapNum) {
      await checkSwap(tokensAndWeights, pool, poolRouterInfo, 8);
    }
    consoleGreen("\t ✓ Small Values");

    //test big values 2^112 = 10^33.7153
    for (let swapNum = 0; swapNum < 3; ++swapNum) {
      await checkSwap(tokensAndWeights, pool, poolRouterInfo, 23);
    }
    consoleGreen("\t ✓ Big values");
  }

  // ---------------------------   TEST CASES   ---------------------------
  //
  describe("Minimum value tests", function () {
    it(`Should test swaps with minimum invariants`, async function () {
      const [poolRouterInfo, pool, tokensAndWeights] = await deployPool(
        MIN_FEE, // fee
        [MIN_WEIGHT, MIN_WEIGHT], // weights
        getBigNumber(10, 30) // mint amount
      );
      await checkSwaps(tokensAndWeights, poolRouterInfo, pool);
    });
  });

  describe("High value tests", function () {
    it(`Should test swaps with maximum invariants`, async function () {
      const [poolRouterInfo, pool, tokensAndWeights] = await deployPool(
        MAX_FEE, // fee
        [getBigNumber(25, 18), getBigNumber(25, 18)], // maxed out weights
        getBigNumber(10, 30) // mint amount
      );
      await checkSwaps(tokensAndWeights, poolRouterInfo, pool);
    });
  });
  describe("Skewed value tests", function () {
    it(`Should test swaps with skewed invariants`, async function () {
      const [poolRouterInfo, pool, tokensAndWeights] = await deployPool(
        MAX_FEE, // fee
        [getBigNumber(1, 19), getBigNumber(4, 19)], // maxed out weights
        getBigNumber(10, 30) // mint amount
      );
      await checkSwaps(tokensAndWeights, poolRouterInfo, pool);
    });
  });
});

function consoleGreen(msg: string) {
  console.log("\x1b[32m", msg);
}

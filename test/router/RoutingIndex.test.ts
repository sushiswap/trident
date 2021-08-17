//@ts-nocheck
import { BigNumber } from "@ethersproject/bignumber";
import { ethers } from "hardhat";
import { getBigNumber, getIntegerRandomValue } from "../utilities";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Contract, ContractFactory } from "ethers";
import { calcOutByIn } from "@sushiswap/sdk";
import seedrandom from "seedrandom";

// CONTRACT CONSTANTS
const testSeed = "3"; // Change it to change random generator values
const rnd = seedrandom(testSeed); // random [0, 1)
const BASE = 10 ** 18;
const MIN_TOKENS = 2;
const MAX_TOKENS = 8;
const MIN_FEE = BASE / 10 ** 6;
const MAX_FEE = BASE / 10;
const MIN_WEIGHT = BASE;
const MAX_WEIGHT = BASE * 50;
const MAX_TOTAL_WEIGHT = BASE * 50;
const MAX_IN_RATIO = BASE / 2;
const MAX_OUT_RATIO = BASE / 3 + 1;

// ------------- PARAMETERS -------------
// alice's usdt/usdc balance
const aliceUSDTBalance: BigNumber = getBigNumber("100000000000000000");
const aliceUSDCBalance: BigNumber = getBigNumber("100000000000000000");

// what each ERC20 is deployed with
const ERCDeployAmount: BigNumber = getBigNumber("1000000000000000000");

// what gets minted for alice on the pool
const poolMintAmount: BigNumber = getBigNumber("1000");

// token weights passed into the pool
const tokenWeights: BigNumber[] = [getBigNumber("10"), getBigNumber("10")];

// pool swap fee
const poolSwapFee: number | BigNumber = 1000000000000;

// -------------         -------------

interface ExactInputSingleParams {
  amountIn: BigNumber;
  amountOutMinimum: BigNumber;
  pool: string;
  tokenIn: string;
  data: string;
}

interface PoolInfo {
  type: string;
  reserve0: BigNumber;
  reserve1: BigNumber;
  weight0: BigNumber;
  weight1: BigNumber;
  fee: number;
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
    fee: number,
    weightedTokens: number[],
    toMint: BigNumber
  ): Promise<[PoolInfo, Contract, tokenAndWeight[]]> {
    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("IndexPoolFactory");
    const SwapRouter = await ethers.getContractFactory("TridentRouter");
    Pool = await ethers.getContractFactory("IndexPool");
    [alice, feeTo] = await ethers.getSigners();

    // deploy erc20's
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

    console.log("checkpoint 1");

    const [t0, t1]: Contract[] =
      usdt.address.toUpperCase() < usdc.address.toUpperCase()
        ? [usdt, usdc]
        : [usdc, usdt];

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address[]", "uint256[]", "uint256"],
      [[t1.address, t0.address], weightedTokens, fee]
    );

    let tokensAndweights: tokenAndWeight[] = [
      { token: t1, weight: weightedTokens[0] },
      { token: t0, weight: weightedTokens[1] },
    ];

    console.log("checkpoint2");
    let tx = await (
      await masterDeployer.deployPool(tridentPoolFactory.address, deployData)
    ).wait();
    const pool: Contract = await Pool.attach(tx.events[1].args.pool);

    console.log("checkpoint 2.5");

    await bento.transfer(
      usdt.address,
      alice.address,
      pool.address,
      aliceUSDTBalance
    );
    await bento.transfer(
      usdc.address,
      alice.address,
      pool.address,
      aliceUSDCBalance
    );
    await bento.transfer(
      weth.address,
      alice.address,
      pool.address,
      aliceUSDCBalance
    );

    console.log("checkpoint 3");
    await pool.mint(
      ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256"],
        [alice.address, toMint]
      )
    );

    console.log("checkpoint 4");
    const poolInfo: PoolInfo = {
      type: "Weighted",
      reserve0: aliceUSDTBalance,
      reserve1: aliceUSDCBalance,
      weight0: weightedTokens[0],
      weight1: weightedTokens[1],
      fee: fee,
    };

    return [poolInfo, pool, tokensAndweights];
  }

  async function checkSwap(
    tokensAndWeights: tokenAndWeight[],
    amountIn: BigNumber,
    poolRouterInfo: PoolInfo,
    pool: Contract,
    swapAmountExp: number
  ) {
    [value, bnValue] = getIntegerRandomValue(swapAmountExp, rnd);
    let params: ExactInputSingleParams = {
      amountIn: bnValue,
      amountOutMinimum: 0,
      pool: pool.address,
      tokenIn: tokensAndWeights[0].token.address,
      data: encodeSwapData(
        tokensAndWeights[0].token.address,
        tokensAndWeights[1].token.address,
        alice.address,
        false,
        amountIn
      ),
    };
    poolRouterInfo.reserve0 = await bento.balanceOf(
      tokensAndWeights[0].token.address,
      pool.address
    );
    poolRouterInfo.reserve1 = await bento.balanceOf(
      tokensAndWeights[1].token.address,
      pool.address
    );

    await router.connect(alice).exactInputSingle(params);
  }

  describe("Check min weight with 2 tokens", function () {
    it(`Test min fee 2 tokens`, async function () {
      const [poolRouterInfo, pool, tokensAndWeights] = await deployPool(
        1000000000000, // fee
        [getBigNumber(10), getBigNumber(10)], // tokens & their weights
        getBigNumber(10) // toMint
      );

      let poolInfo = {
        reserve0: ERCDeployAmount,
        reserve1: ERCDeployAmount,
        weight0: getBigNumber(10),
        weight1: getBigNumber(10),
        fee: 1000000000000,
      };

      // this renders a negative number
      let out = calcOutByIn(poolInfo, getBigNumber(1), false);

      // await checkSwap(tokensAndWeights, BigNumber(1), poolRouterInfo, pool, 3)
    });
    // test for min fee + min weights + min tokens
    // max fee + max weight + max tokens
    // min fee + min weight + max tokens
    // min fee + max weight + min tokens
  });
});

// it("should swap and work correctly", async function () {
//   const pool: Contract = await deployPool();

//   const poolInfo: PoolInfo = {
//     type: "Weighted",
//     reserve0: aliceUSDTBalance,
//     reserve1: aliceUSDCBalance,
//     weight0: tokenWeights[0],
//     weight1: tokenWeights[1],
//     fee: poolSwapFee,
//   };

//   const routerInput: ExactInputSingleParams = {
//     amountIn: getBigNumber(1),
//     amountOutMinimum: getBigNumber(0),
//     pool: pool.address,
//     tokenIn: usdt.address,
//     data: encodeSwapData(usdt.address, usdc.address, alice.address, false, getBigNumber(1)),
//   }

//   let usdcBefore: BigNumber = await bento.balanceOf(usdc.address, alice.address);
//   let before: BigNumber = await bento.balanceOf(usdc.address, alice.address);
//   await router.connect(alice).exactInputSingle(routerInput);
//   let after: BigNumber = await bento.balanceOf(usdc.address, alice.address);
//   let usdcAfter: BigNumber = await bento.balanceOf(usdc.address, alice.address);
//   console.log(usdcBefore.toString(), usdcAfter.toString());
//   console.log(after.sub(before).toString());

//   const predictedOut = calcOutByIn(poolInfo, getBigNumber(1), true);
//   console.log(predictedOut);
// });

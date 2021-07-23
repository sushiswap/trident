const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const seedrandom = require("seedrandom")
const { calcOutByIn, calcInByOut } = require("@sushiswap/sdk");
const { prepare, deploy, getBigNumber } = require("./utilities");

const testSeed = '1';   // Change it to change random generator values
const rnd = seedrandom(testSeed); // random [0, 1)

function getIntegerRandomValue(exp) {
  if (exp <= 15) {
    const value = Math.floor(rnd()*Math.pow(10, exp));
    return [value, BigNumber.from(value)];
  } else {
    const random = Math.floor(rnd()*1e15);
    const value = random*Math.pow(10, exp-15);
    const bnValue = BigNumber.from(10).pow(exp-15).mul(random);
    return [value, bnValue];
  }
}

function areCloseValues(v1, v2, threshould) {
  if (threshould == 0)
    return v1 == v2;
  if  (v1 < 1/threshould)
    return Math.abs(v1-v2) < 1;
  return Math.abs(v1/v2 - 1) < threshould;
}

describe("ConstantProductPool Typescript == Solidity check", function () {
  let alice, feeTo, usdt, usdc, weth, bento, masterDeployer, mirinPoolFactory, router, Pool;

  async function createConstantProductPool(fee, res0exp, res1exp) {
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256"],
      [usdt.address, usdc.address, Math.round(fee*10_000)]
    );
    const pool = await Pool.attach(
      (await (await masterDeployer.deployPool(mirinPoolFactory.address, deployData)).wait()).events[0].args[0]
    );

    const [jsVal0, bnVal0] = getIntegerRandomValue(res0exp);
    const [jsVal1, bnVal1] = res1exp == undefined ? [jsVal0, bnVal0] : getIntegerRandomValue(res1exp);
    await bento.transfer(usdt.address, alice.address, pool.address, bnVal0);
    await bento.transfer(usdc.address, alice.address, pool.address, bnVal1);
    await pool.mint(alice.address);
  
    const poolInfo = {
      type: 'ConstantProduct',
      reserve0: jsVal0,
      reserve1: jsVal1,
      fee
    }

    return [poolInfo, pool];
  }

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("ConstantProductPoolFactory");
    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    Pool = await ethers.getContractFactory("ConstantProductPool");

    weth = await ERC20.deploy("WETH", "WETH", getBigNumber("10000000"));
    usdt = await ERC20.deploy("USDT", "USDT", getBigNumber("10000000"));
    usdc = await ERC20.deploy("USDC", "USDC", getBigNumber("10000000"));
    bento = await Bento.deploy(usdt.address);
    masterDeployer = await Deployer.deploy(17, feeTo.address, bento.address);
    mirinPoolFactory = await PoolFactory.deploy();
    router = await SwapRouter.deploy(weth.address, bento.address);

    // Whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(mirinPoolFactory.address);

    // Whitelist Router on BentoBox
    await bento.whitelistMasterContract(router.address, true);
    // Approve BentoBox token deposits
    await usdc.approve(bento.address, getBigNumber("10000000"));
    await usdt.approve(bento.address, getBigNumber("10000000"));
    // Make BentoBox token deposits
    await bento.deposit(usdc.address, alice.address, alice.address, getBigNumber("1000000"), 0);
    await bento.deposit(usdt.address, alice.address, alice.address, getBigNumber("1000000"), 0);
    // Approve Router to spend 'alice' BentoBox tokens
    await bento.setMasterContractApproval(alice.address, router.address, true, "0", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000");
  })

  it("AmountOut should differ less than 1e-14", async function() {
    for (let mintNum = 0; mintNum < 10; ++mintNum) {
      const [poolRouterInfo, pool] = await createConstantProductPool(0.003, 19, 19);

      for (let swapNum = 0; swapNum < 50; ++swapNum) {
        const [jsValue, bnValue] = getIntegerRandomValue(17);
        const amountOutPool = (await pool.getAmountOut(usdt.address, usdc.address, bnValue)).toString();
        const amountOutPrediction = calcOutByIn(poolRouterInfo, jsValue, true);
        expect(areCloseValues(amountOutPrediction, amountOutPool, 1e-14)).equals(true);
        const amounInExpected = calcInByOut(poolRouterInfo, amountOutPrediction, true);
        expect(areCloseValues(amounInExpected, jsValue, 1e-14)).equals(true);
      }

    }
  });
})

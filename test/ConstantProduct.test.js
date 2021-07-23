const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const seedrandom = require("seedrandom")
const { calcOutByIn, calcInByOut } = require("@sushiswap/sdk");
const { prepare, deploy, getBigNumber } = require("./utilities");

const testSeed = '0';   // Change it to change random generator output values
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

describe("ConstantProductPool Typescript == Solidity check", function () {
  let alice, feeTo, usdt, usdc, weth, bento, masterDeployer, mirinPoolFactory, router, pool;

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("ConstantProductPoolFactory");
    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    const Pool = await ethers.getContractFactory("ConstantProductPool");

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
    // Pool deploy data
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint8", "uint256"],
      [usdt.address, usdc.address, 30, 200000]
    );
    pool = await Pool.attach(
      (await (await masterDeployer.deployPool(mirinPoolFactory.address, deployData)).wait()).events[0].args[0]
    );
  })

  it("AmountOut should differ less than 1e-14", async function() {
    //for (let mintNum = 0; mintNum < 2; ++mintNum) {
      await bento.transfer(usdc.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await bento.transfer(usdt.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await pool.mint(alice.address);

      const pool2 = {
        type: 'ConstantProduct',
        reserve0: Math.pow(10, 19),
        reserve1: Math.pow(10, 19),
        fee: 0.003
      }

      for (let swapNum = 0; swapNum < 100; ++swapNum) {
        const [jsValue, bnValue] = getIntegerRandomValue(18);
        const amountOutPool = (await pool.getAmountOut(usdt.address, usdc.address, bnValue)).toString();
        const amountOutPrediction = calcOutByIn(pool2, jsValue);
        expect(Math.abs(amountOutPrediction/amountOutPool - 1)).lessThan(1e-14);
        const amounInExpected = calcInByOut(pool2, amountOutPrediction);
        expect(Math.abs(amounInExpected/jsValue - 1)).lessThan(1e-14);
      }

    //   await pool.burn(alice.address, false);
    // }
  });
})

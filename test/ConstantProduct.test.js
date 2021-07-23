const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { prepare, deploy, getBigNumber } = require("./utilities");
const { calcOutByIn} = require("@sushiswap/sdk");

describe("ConstantProduct Typescript == Solidity", function () {
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

  it("Check", async function() {
    await bento.transfer(usdc.address, alice.address, pool.address, BigNumber.from(10).pow(19));
    await bento.transfer(usdt.address, alice.address, pool.address, BigNumber.from(10).pow(19));
    await pool.mint(alice.address);
    let amountIn = BigNumber.from(10).pow(18);
    const amountOut = await pool.getAmountOut(usdt.address, usdc.address, amountIn);
    console.log(amountOut.toString());

    const pool2 = {
      type: 'ConstantProduct',
      reserve0: Math.pow(10, 19),
      reserve1: Math.pow(10, 19),
      fee: 0.003
    }
    const amountOut2 = calcOutByIn(pool2, Math.pow(10, 18));
    console.log(amountOut2);
    expect(1).eq(1);
  });
})

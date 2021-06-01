import { ethers } from "hardhat";
import { expect } from "chai";
import { prepare, deploy, getBigNumber } from "./utilities"
import { BigNumber } from 'ethers';

describe("Router", function () {
  let alice, feeTo, weth, sushi, bento, masterDeployer, mirinPoolFactory, router, pool;

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("MirinPoolFactory");
    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    const Pool = await ethers.getContractFactory("MirinPoolBento");

    weth = await ERC20.deploy("WETH", "ETH", getBigNumber("10000000"));
    sushi = await ERC20.deploy("SUSHI", "SUSHI", getBigNumber("10000000"));
    bento = await Bento.deploy(weth.address);
    masterDeployer = await Deployer.deploy();
    mirinPoolFactory = await PoolFactory.deploy();
    router = await SwapRouter.deploy(weth.address, masterDeployer.address, bento.address);

    // Whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(mirinPoolFactory.address);

    // Whitelist Router on BentoBox
    await bento.whitelistMasterContract(router.address, true);
    // Approve BentoBox token deposits
    await sushi.approve(bento.address, BigNumber.from(10).pow(30));
    await weth.approve(bento.address, BigNumber.from(10).pow(30));
    // Make BentoBox token deposits
    await bento.deposit(sushi.address, alice.address, alice.address, BigNumber.from(10).pow(20), 0);
    await bento.deposit(weth.address, alice.address, alice.address, BigNumber.from(10).pow(20), 0);
    // Approve Router to spend 'alice' BentoBox tokens
    await bento.setMasterContractApproval(alice.address, router.address, true, "0", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000");
    // Pool deploy data
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "address", "uint256", "uint8", "address"],
      [bento.address, weth.address, sushi.address, 50, 30, feeTo.address]
    );
    // Pool initialize data
    const initData = Pool.interface.encodeFunctionData("init");
    pool = await Pool.attach(
      (await (await masterDeployer.deployPool(mirinPoolFactory.address, deployData, initData)).wait()).events[1].args[0]
    );
  })

  describe("Pool", function() {
    it("Pool should have correct tokens", async function() {
      expect(await pool.token0()).eq(weth.address);
      expect(await pool.token1()).eq(sushi.address);
    });

    it("Should add liquidity to the pool", async function() {
      await bento.transfer(sushi.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await bento.transfer(weth.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await pool.mint(alice.address);
      expect(await pool.totalSupply()).gt(1);
    });
  });
})

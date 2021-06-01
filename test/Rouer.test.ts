import { ethers } from "hardhat";
import { expect } from "chai";
import { prepare, deploy, getBigNumber } from "./utilities"
import { BigNumber } from 'ethers';

describe("Router", function () {
  let alice, feeTo, weth, sushi, bento, masterDeployer, mirinPoolFactory, router, Pool;

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("MirinPoolFactory");
    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    Pool = await ethers.getContractFactory("MirinPoolBento");

    weth = await ERC20.deploy("WETH", "ETH", getBigNumber("10000000"));
    sushi = await ERC20.deploy("SUSHI", "SUSHI", getBigNumber("10000000"));
    bento = await Bento.deploy(weth.address);
    masterDeployer = await Deployer.deploy();
    mirinPoolFactory = await PoolFactory.deploy();
    router = await SwapRouter.deploy(weth.address, masterDeployer.address, bento.address);

    // Whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(mirinPoolFactory.address);

    // Whitelist Router on BentoBox
    await bento.whitelistMasterContract(router.address, true)
    // Approve BentoBox token deposits
    await sushi.approve(bento.address, BigNumber.from(10).pow(30))
    await weth.approve(bento.address, BigNumber.from(10).pow(30))
    // Make BentoBox token deposits
    await bento.deposit(sushi.address, alice.address, alice.address, BigNumber.from(10).pow(20), 0)
    await bento.deposit(weth.address, alice.address, alice.address, BigNumber.from(10).pow(20), 0)
    // Approve Router to spend 'alice' BentoBox tokens
    await bento.setMasterContractApproval(alice.address, router.address, true, "0", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000")
  })

  describe("Pool Deployment", function() {
    it("Should deploy a pool", async function() {
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "address", "uint256", "uint8", "address"],
        [bento.address, weth.address, sushi.address, 50, 30, feeTo.address]
      );
      let pool = await Pool.attach(
        (await (await masterDeployer.deployPool(mirinPoolFactory.address, data, "0x")).wait()).events[1].args[0]
      );
      expect(await pool.token0()).eq(weth.address);
      expect(await pool.token1()).eq(sushi.address);
    });
  });
})

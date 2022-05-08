import { expect } from "chai";
import { BigNumber } from "ethers";
import { deployments, ethers } from "hardhat";

import type {
  BentoBoxV1,
  StablePool__factory,
  ERC20Mock,
  ERC20Mock__factory,
  FlashSwapMock,
  FlashSwapMock__factory,
  MasterDeployer,
} from "../../types";
import { initializedStablePool, uninitializedStablePool } from "../fixtures";

describe("Stable Pool", () => {
  before(async () => {
    console.log("Deploy MasterDeployer fixture");
    await deployments.fixture(["MasterDeployer"]);
    console.log("Deployed MasterDeployer fixture");
  });

  beforeEach(async () => {
    //
  });

  describe("#instantiation", () => {
    it("reverts if token0 is zero", async () => {
      const StablePool = await ethers.getContractFactory<StablePool__factory>("StablePool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", 30, false]
      );
      await expect(StablePool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("ZeroAddress()");
    });

    // TODO: fix instantiation allowed if token1 is zero
    it("deploys if token1 is zero", async () => {
      const StablePool = await ethers.getContractFactory<StablePool__factory>("StablePool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000", 30, false]
      );
      await expect(StablePool.deploy(deployData, masterDeployer.address)).to.not.be.revertedWith("ZeroAddress()");
    });

    it("reverts if token0 and token1 are identical", async () => {
      const StablePool = await ethers.getContractFactory<StablePool__factory>("StablePool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000001", 30, false]
      );
      await expect(StablePool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("IdenticalAddress()");
    });
    it("reverts if swap fee more than the max fee", async () => {
      const StablePool = await ethers.getContractFactory<StablePool__factory>("StablePool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 10001, false]
      );
      await expect(StablePool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("InvalidSwapFee()");
    });
  });

  describe("#mint", function () {
    it("reverts if insufficient liquidity minted", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      await token0.transfer(pool.address, 1);
      await token1.transfer(pool.address, 1);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await expect(pool.mint(mintData)).to.be.revertedWith("InsufficientLiquidityMinted()");
    });

    it("adds more liqudity", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await token1.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData);
    });

    it("removes liquidity", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const bob = await ethers.getNamedSigner("bob");
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await token1.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData);

      await token0.transfer(bento.address, ethers.utils.parseEther("1"));
      await token1.transfer(bento.address, ethers.utils.parseEther("1"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      const mintData2 = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData2);

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));

      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      const bal1 = await token0.balanceOf(bob.address);
      const bal2 = await token1.balanceOf(bob.address);

      await pool.burn(burnData);

      const bal3 = await token0.balanceOf(bob.address);
      const bal4 = await token1.balanceOf(bob.address);
      console.log(bal3.sub(bal1).toString());
      console.log(bal4.sub(bal2).toString());
    });

    it("swap", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const alice = await ethers.getNamedSigner("alice");
      const feeTo = await ethers.getNamedSigner("barFeeTo");
      const bob = await ethers.getNamedSigner("bob");

      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await token1.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      console.log((await pool.kLast()).toString());
      console.log((await pool.balanceOf(feeTo.address)).toString());
      await pool.mint(mintData);
      console.log((await pool.kLast()).toString());
      console.log((await pool.balanceOf(feeTo.address)).toString());
      await token0.transfer(bento.address, ethers.utils.parseEther("1"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      const swapData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, alice.address, true]
      );
      await pool.swap(swapData);
      console.log((await token1.balanceOf(alice.address)).toString());
      console.log((await pool.kLast()).toString());
      console.log((await pool.balanceOf(feeTo.address)).toString());

      await token0.transfer(bento.address, ethers.utils.parseEther("1"));
      await token1.transfer(bento.address, ethers.utils.parseEther("1"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      const mintData2 = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData2);
      console.log((await pool.kLast()).toString());
      console.log((await pool.balanceOf(feeTo.address)).toString());

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));

      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      const bal1 = await token0.balanceOf(bob.address);
      const bal2 = await token1.balanceOf(bob.address);

      await pool.burn(burnData);

      const bal3 = await token0.balanceOf(bob.address);
      const bal4 = await token1.balanceOf(bob.address);
      console.log(bal3.sub(bal1).toString());
      console.log(bal4.sub(bal2).toString());
    });
  });
});

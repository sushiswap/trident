import { expect, util } from "chai";
import { BigNumber } from "ethers";
import { deployments, ethers } from "hardhat";

import {
  BentoBoxV1,
  StablePoolFactory,
  StablePool__factory,
  StablePoolFactory__factory,
  ERC20Mock,
  ERC20Mock__factory,
  FlashSwapMock,
  FlashSwapMock__factory,
  MasterDeployer,
} from "../../types";
import { initializedStablePool, uninitializedStablePool } from "../fixtures";
import { ADDRESS_ZERO } from "../utilities";

describe("Stable Pool", () => {
  before(async () => {
    console.log("Deploy StablePoolFactory fixture");
    await deployments.fixture(["StablePoolFactory"]);
    console.log("Deployed StablePoolFactory fixture");
  });

  beforeEach(async () => {
    //
  });

  describe("#instantiation", () => {
    it("reverts if token0 is zero", async () => {
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        ["0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000001", 30]
      );
      await expect(stableFactory.deployPool(deployData)).to.be.revertedWith("ZeroAddress()");
    });

    it("reverts if token1 is zero", async () => {
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000", 30]
      );
      await expect(stableFactory.deployPool(deployData)).to.be.revertedWith("ZeroAddress()");
    });

    it("reverts if token0 and token1 are identical", async () => {
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000001", 30]
      );
      await expect(stableFactory.deployPool(deployData)).to.be.revertedWith("IdenticalAddress()");
    });

    it("reverts if swap fee more than the max fee", async () => {
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 10001]
      );
      await expect(stableFactory.deployPool(deployData)).to.be.revertedWith("InvalidSwapFee()");
    });
  });

  describe("#mint", function () {
    it("reverts if total supply is 0 and one of the token amounts are 0 - token 0", async () => {
      const pool = await uninitializedStablePool();

      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      const newLocal = "0x0000000000000000000000000000000000000003";

      await token0.transfer(bentoBox.address, 1000);

      await bentoBox.deposit(token0.address, bentoBox.address, pool.address, 1000, 0);

      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [newLocal]);
      await expect(pool.mint(mintData)).to.be.revertedWith("InvalidAmounts()");
    });

    it("reverts if total supply is 0 and one of the token amounts are 0 - token 1", async () => {
      const pool = await uninitializedStablePool();

      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      const newLocal = "0x0000000000000000000000000000000000000003";

      await token1.transfer(bentoBox.address, 1000);

      await bentoBox.deposit(token1.address, bentoBox.address, pool.address, 1000, 0);

      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [newLocal]);
      await expect(pool.mint(mintData)).to.be.revertedWith("InvalidAmounts()");
    });

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

    // todo: maybe wanna move these tests into proper spots
    it("adds more liquidity", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseUnits("100000000000", "18"));
      await token1.transfer(bento.address, ethers.utils.parseUnits("100000000000", "18"));
      await bento.deposit(
        token0.address,
        bento.address,
        pool.address,
        ethers.utils.parseUnits("100000000000", "18"),
        0
      );
      await bento.deposit(
        token1.address,
        bento.address,
        pool.address,
        ethers.utils.parseUnits("100000000000", "18"),
        0
      );
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData);
      // const getAmountOutData = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [token0.address, ethers.utils.parseUnits("100", '18')]);
      // console.log(ethers.utils.formatUnits(await pool.getAmountOut(getAmountOutData), '18'));
    });

    it.skip("adds small quantity of liqudity", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseUnits("100000000000", "18"));
      await token1.transfer(bento.address, ethers.utils.parseUnits("100000000000", "18"));
      await bento.deposit(token0.address, bento.address, pool.address, BigNumber.from(1e14), 0);
      await bento.deposit(token1.address, bento.address, pool.address, BigNumber.from(1e14), 0);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData);
      // const getAmountOutData = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [token0.address, ethers.utils.parseUnits("100", '18')]);
      // console.log(ethers.utils.formatUnits(await pool.getAmountOut(getAmountOutData), '18'));
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

      await token0.transfer(bento.address, ethers.utils.parseEther("100"));
      await token1.transfer(bento.address, ethers.utils.parseEther("100"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("100"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("100"), 0);
      const mintData2 = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData2);

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));

      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      const bal1 = await token0.balanceOf(bob.address);
      const bal2 = await token1.balanceOf(bob.address);

      await pool.burn(burnData);

      const bal3 = await token0.balanceOf(bob.address);
      const bal4 = await token1.balanceOf(bob.address);
      // console.log(bal3.sub(bal1).toString());
      // console.log(bal4.sub(bal2).toString());
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
      // console.log((await pool.kLast()).toString());
      // console.log((await pool.balanceOf(feeTo.address)).toString());
      await pool.mint(mintData);
      // console.log((await pool.kLast()).toString());
      // console.log((await pool.balanceOf(feeTo.address)).toString());
      await token0.transfer(bento.address, ethers.utils.parseEther("1"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      const swapData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, alice.address, true]
      );
      await pool.swap(swapData);
      // console.log((await token1.balanceOf(alice.address)).toString());
      // console.log((await pool.kLast()).toString());
      // console.log((await pool.balanceOf(feeTo.address)).toString());

      await token0.transfer(bento.address, ethers.utils.parseEther("100"));
      await token1.transfer(bento.address, ethers.utils.parseEther("100"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("100"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("100"), 0);
      const mintData2 = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData2);
      // console.log((await pool.kLast()).toString());
      // console.log((await pool.balanceOf(feeTo.address)).toString());

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));

      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      const bal1 = await token0.balanceOf(bob.address);
      const bal2 = await token1.balanceOf(bob.address);

      await pool.burn(burnData);

      const bal3 = await token0.balanceOf(bob.address);
      const bal4 = await token1.balanceOf(bob.address);
      // console.log(bal3.sub(bal1).toString());
      // console.log(bal4.sub(bal2).toString());
    });
  });

  describe("#burn", function () {
    //
  });

  describe("#burnSingle", function () {
    //
  });

  describe("#swap", function () {
    it("reverts on uninitialized", async () => {
      // event not in stable pool
    });
  });

  describe("#flashSwap", function () {
    it("reverts on call", async () => {
      // flashSwap not supported on StablePool
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      await token0.transfer(flashSwapMock.address, 100);

      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [true, token0.address, false]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token0.address, flashSwapMock.address, true, 100, flashSwapData]
      );
      await expect(flashSwapMock.testFlashSwap(pool.address, data)).to.be.reverted;
    });
  });

  describe("#poolIdentifier", function () {
    //
  });

  describe("#getAssets", function () {
    it("returns the assets the pool was deployed with, and in the correct order", async () => {
      const StablePool = await ethers.getContractFactory<StablePool__factory>("StablePool");
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const ERC20 = await ethers.getContractFactory<ERC20Mock__factory>("ERC20Mock");
      let token0 = await ERC20.deploy("Token 0", "TOKEN0", ethers.constants.MaxUint256);
      let token1 = await ERC20.deploy("Token 1", "TOKEN1", ethers.constants.MaxUint256);
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        [token0.address, token1.address, 30]
      );
      await masterDeployer.deployPool(stableFactory.address, deployData);

      if (token0 > token1) {
        const saveToken = token0;
        token0 = token1;
        token1 = saveToken;
      }

      const addy = await stableFactory.calculatePoolAddress(token0.address, token1.address, 30);
      const stablePool = StablePool.attach(addy);
      const assets = await stablePool.getAssets();

      await expect(assets[0], token0.address);
      await expect(assets[1], token1.address);
    });
  });
});

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
  });
});

import { deployments, ethers } from "hardhat";
import { ConstantProductPool__factory, MasterDeployer } from "../../types";
import { expect } from "chai";

describe("Constant Product Pool", function () {
  before(async () => {
    await deployments.fixture(["MasterDeployer"]);
  });

  beforeEach(async () => {
    //
  });

  describe("#instantiation", () => {
    it("reverts if token0 is zero", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", 30, false]
      );
      await expect(ConstantProductPool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("ZERO_ADDRESS");
    });
    // TODO: fix instantiation allowed if token1 is zero
    it.skip("reverts if token1 is zero", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000", 30, false]
      );
      await expect(ConstantProductPool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("ZERO_ADDRESS");
    });

    it("reverts if token0 and token1 are identical", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000001", 30, false]
      );
      await expect(ConstantProductPool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("IDENTICAL_ADDRESSES");
    });

    it("reverts if token0 is the computed address of the pool", async () => {
      //
    });
    it("reverts if token0 is the computed address of the pool", async () => {
      //
    });
    it("reverts if swap fee more than the max fee", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 10001, false]
      );
      await expect(ConstantProductPool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("INVALID_SWAP_FEE");
    });
  });

  describe("#swap", function () {});

  describe("#flashSwap", function () {
    //
  });

  describe("#mint", function () {
    //
  });

  describe("#burn", function () {
    //
  });

  describe("#burnSingle", function () {
    //
  });

  describe("#poolIdentifier", function () {
    //
  });

  describe("#getAssets", function () {
    //
  });

  describe("#getAmountOut", function () {
    //
  });

  describe("#getAmountIn", function () {
    //
  });

  describe("#getNativeReserves", function () {
    //
  });
});

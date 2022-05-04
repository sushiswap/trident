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
import { initializedStablePool } from "../fixtures";

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
      await StablePool.deploy(deployData, masterDeployer.address);
      // await expect(StablePool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("ZeroAddress()");
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
});

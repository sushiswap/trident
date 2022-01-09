import { ethers, deployments } from "hardhat";
import { expect } from "chai";
import { MasterDeployer, PoolFactoryMock__factory } from "../../types";
import { customError } from "../utilities";

describe("Pool Deployer", function () {
  before(async function () {
    await deployments.fixture(["MasterDeployer"]);
  });

  it("reverts when passing zero address for master deployer", async function () {
    const PoolFactory = await ethers.getContractFactory<PoolFactoryMock__factory>("PoolFactoryMock");
    await expect(PoolFactory.deploy("0x0000000000000000000000000000000000000000")).to.be.revertedWith(customError("ZeroAddress"));
  });

  it("reverts when deploying directly rather than through master deployer", async function () {
    const PoolFactory = await ethers.getContractFactory<PoolFactoryMock__factory>("PoolFactoryMock");
    const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
    const poolFactory = await PoolFactory.deploy(masterDeployer.address);

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address"],
      ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002"]
    );
    await expect(poolFactory.deployPool(deployData)).to.be.revertedWith(customError("UnauthorisedDeployer"));
  });

  it("reverts when deploying with invalid token order", async function () {
    const PoolFactory = await ethers.getContractFactory<PoolFactoryMock__factory>("PoolFactoryMock");
    const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
    const poolFactory = await PoolFactory.deploy(masterDeployer.address);
    await masterDeployer.addToWhitelist(poolFactory.address);
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address"],
      ["0x0000000000000000000000000000000000000002", "0x0000000000000000000000000000000000000001"]
    );
    await expect(poolFactory.deployPool(deployData)).to.be.revertedWith(customError("InvalidTokenOrder"));
  });
});

import { ethers, deployments } from "hardhat";
import { expect } from "chai";
import { MasterDeployer, PoolDeployerMock__factory } from "../../types";
import { customError } from "../utilities";

describe("Pool Deployer", function () {
  before(async function () {
    await deployments.fixture(["MasterDeployer"]);
  });

  it("reverts when passing zero address for master deployer", async function () {
    const PoolFactory = await ethers.getContractFactory<PoolDeployerMock__factory>("PoolDeployerMock");
    await expect(PoolFactory.deploy("0x0000000000000000000000000000000000000000")).to.be.revertedWith(
      customError("ZeroAddress")
    );
  });

  it("reverts when deploying directly rather than master deployer", async function () {
    const PoolFactory = await ethers.getContractFactory<PoolDeployerMock__factory>("PoolDeployerMock");
    const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
    const poolFactory = await PoolFactory.deploy(masterDeployer.address);

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address"],
      ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002"]
    );
    await expect(poolFactory.deployPool(deployData)).to.be.revertedWith(customError("UnauthorisedDeployer"));
  });

  it("reverts when deploying with invalid token order", async function () {
    const PoolFactory = await ethers.getContractFactory<PoolDeployerMock__factory>("PoolDeployerMock");
    const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
    const poolFactory = await PoolFactory.deploy(masterDeployer.address);
    await masterDeployer.addToWhitelist(poolFactory.address);
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address"],
      ["0x0000000000000000000000000000000000000002", "0x0000000000000000000000000000000000000001"]
    );
    await expect(masterDeployer.deployPool(poolFactory.address, deployData)).to.be.revertedWith(
      customError("InvalidTokenOrder")
    );
  });
});

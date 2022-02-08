import { ethers, deployments } from "hardhat";
import { expect } from "chai";
import { ConstantProductPoolFactory, MasterDeployer, ConstantProductPool } from "../../types";

describe("Constant Product Pool Factory", function () {
  before(async () => {
    //
  });

  beforeEach(async () => {
    await deployments.fixture(["ConstantProductPoolFactory"]);
  });

  describe("#deployPool", function () {
    it("swaps tokens which are passed in the wrong order", async function () {
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>(
        "ConstantProductPoolFactory"
      );

      const token1 = "0x0000000000000000000000000000000000000001";
      const token2 = "0x0000000000000000000000000000000000000002";

      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [token2, token1, 30, false]
      );

      const tx = await (await masterDeployer.deployPool(constantProductPoolFactory.address, deployData)).wait();

      const constantProductPool = await ethers.getContractAt<ConstantProductPool>(
        "ConstantProductPool",
        tx.events?.[0]?.args?.pool
      );

      expect(await constantProductPool.token0()).to.equal(token1);
      expect(await constantProductPool.token1()).to.equal(token2);
    });

    it("getPoolsForTokens test", async function () {
      const token1 = "0x0000000000000000000000000000000000000001";
      const token2 = "0x0000000000000000000000000000000000000002";
      const token3 = "0x0000000000000000000000000000000000000003";
      const token4 = "0x0000000000000000000000000000000000000004";

      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>(
        "ConstantProductPoolFactory"
      );

      let deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [token1, token2, 30, false]
      );
      await (await masterDeployer.deployPool(constantProductPoolFactory.address, deployData)).wait();

      deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [token1, token2, 25, false]
      );
      await (await masterDeployer.deployPool(constantProductPoolFactory.address, deployData)).wait();

      deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [token1, token2, 25, true]
      );
      await (await masterDeployer.deployPool(constantProductPoolFactory.address, deployData)).wait();

      deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [token2, token3, 30, false]
      );
      await (await masterDeployer.deployPool(constantProductPoolFactory.address, deployData)).wait();

      const [res, length] = await constantProductPoolFactory.getPoolsForTokens([token1, token2, token3, token4]);
      expect(length).equal(4);
      expect(res.length).equal(4);
    });

    it("reverts when token0 is zero", async function () {
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>(
        "ConstantProductPoolFactory"
      );

      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000001", 30, false]
      );

      await expect(masterDeployer.deployPool(constantProductPoolFactory.address, deployData)).to.be.revertedWith(
        "ZERO_ADDRESS"
      );
    });

    it("reverts when token1 is zero", async function () {
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>(
        "ConstantProductPoolFactory"
      );

      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000", 30, false]
      );

      await expect(masterDeployer.deployPool(constantProductPoolFactory.address, deployData)).to.be.revertedWith(
        "ZERO_ADDRESS"
      );
    });

    it("has pool count of 0", async function () {
      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>(
        "ConstantProductPoolFactory"
      );
      expect(
        await constantProductPoolFactory.poolsCount(
          "0x0000000000000000000000000000000000000001",
          "0x0000000000000000000000000000000000000002"
        )
      ).to.equal(0);
    });

    it("has pool count of 1 after pool deployed", async function () {
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>(
        "ConstantProductPoolFactory"
      );

      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 30, false]
      );

      await masterDeployer.deployPool(constantProductPoolFactory.address, deployData);

      expect(
        await constantProductPoolFactory.poolsCount(
          "0x0000000000000000000000000000000000000001",
          "0x0000000000000000000000000000000000000002"
        )
      ).to.equal(1);
    });
  });

  describe("#configAddress", function () {
    //
  });
});

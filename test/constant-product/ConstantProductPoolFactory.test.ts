import { ethers, deployments } from "hardhat";
import { expect } from "chai";
import { ConstantProductPoolFactory, MasterDeployer, ConstantProductPool } from "../../types";

describe("Constant Product Pool Factory", function () {
  before(async function () {
    await deployments.fixture(["ConstantProductPoolFactory"]);
  });

  beforeEach(async function () {
    //
  });

  describe("#deployPool", function () {
    it("swaps tokens which are passed in the wrong order", async function () {
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");

      const token1 = "0x0000000000000000000000000000000000000001";
      const token2 = "0x0000000000000000000000000000000000000002";

      const deployData = ethers.utils.defaultAbiCoder.encode(["address", "address", "uint256", "bool"], [token2, token1, 30, false]);

      const tx = await (await masterDeployer.deployPool(constantProductPoolFactory.address, deployData)).wait();

      const constantProductPool = await ethers.getContractAt<ConstantProductPool>("ConstantProductPool", tx.events?.[0]?.args?.pool);

      expect(await constantProductPool.token0()).to.equal(token1);
      expect(await constantProductPool.token1()).to.equal(token2);
    });

    it("has pool count of 0", async function () {
      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");
      expect(
        await constantProductPoolFactory.poolsCount(
          "0x0000000000000000000000000000000000000001",
          "0x0000000000000000000000000000000000000002"
        )
      ).to.equal(0);
    });

    it("has pool count of 1 after pool deployed", async function () {
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

      const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");

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

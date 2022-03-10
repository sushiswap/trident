import { keccak256, pack } from "@ethersproject/solidity";

import { MAX_FEE } from "../utilities";
import { bytecode as constantProductPoolBytecode } from "../../artifacts/contracts/pool/constant-product/ConstantProductPool.sol/ConstantProductPool.json";
import { customError } from "../utilities";
import { defaultAbiCoder } from "@ethersproject/abi";
import { ethers } from "hardhat";
import { expect } from "chai";
import { getCreate2Address } from "@ethersproject/address";

describe("MasterDeployer", function () {
  before(async function () {
    this.feeTo = await ethers.getNamedSigner("feeTo");
    this.MasterDeployer = await ethers.getContractFactory("MasterDeployer");
    this.ConstantProductPoolFactory = await ethers.getContractFactory("ConstantProductPoolFactory");
    this.BentoBox = await ethers.getContractFactory("BentoBoxV1");
    this.ERC20 = await ethers.getContractFactory("ERC20Mock");
    this.sushi = await this.ERC20.deploy("SushiToken", "SUSHI", ethers.constants.MaxUint256);
    await this.sushi.deployed();
    this.WETH9 = await ethers.getContractFactory("WETH9");
    this.weth = await this.WETH9.deploy();
    await this.weth.deployed();
    this.bentoBox = await this.BentoBox.deploy(this.weth.address);
    await this.bentoBox.deployed();
  });

  it("Reverts on invalid fee", async function () {
    await expect(
      this.MasterDeployer.deploy(MAX_FEE.add(1), this.feeTo.address, this.bentoBox.address)
    ).to.be.revertedWith("InvalidBarFee");
  });

  it("Reverts on fee to zero address", async function () {
    await expect(
      this.MasterDeployer.deploy(MAX_FEE, ethers.constants.AddressZero, this.bentoBox.address)
    ).to.be.revertedWith("ZeroAddress");
  });

  it("Reverts on bento zero address", async function () {
    await expect(
      this.MasterDeployer.deploy(MAX_FEE, this.feeTo.address, ethers.constants.AddressZero)
    ).to.be.revertedWith("ZeroAddress");
  });

  beforeEach(async function () {
    this.masterDeployer = await this.MasterDeployer.deploy(MAX_FEE, this.feeTo.address, this.bentoBox.address);
    await this.masterDeployer.deployed();
    this.constantProductPoolFactory = await this.ConstantProductPoolFactory.deploy(this.masterDeployer.address);
  });

  describe("#deployPool", async function () {
    it("Reverts on non-whitelisted factory", async function () {
      const deployData = defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [...[this.weth.address, this.sushi.address].sort(), 30, true]
      );

      await expect(
        this.masterDeployer.deployPool(this.constantProductPoolFactory.address, deployData)
      ).to.be.revertedWith("NotWhitelisted");
    });

    it("Adds address to pools array", async function () {
      await this.masterDeployer.addToWhitelist(this.constantProductPoolFactory.address);

      const deployData = defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [...[this.weth.address, this.sushi.address].sort(), 30, true]
      );

      await this.masterDeployer.deployPool(this.constantProductPoolFactory.address, deployData);
    });

    it("Reverts on direct deployment via factory", async function () {
      const deployData = defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [...[this.weth.address, this.sushi.address].sort(), 30, true]
      );

      await expect(this.constantProductPoolFactory.deployPool(deployData)).to.be.revertedWith(
        customError("UnauthorisedDeployer")
      );
    });

    // TODO: Fix this
    it("Emits event on successful deployment", async function () {
      await this.masterDeployer.addToWhitelist(this.constantProductPoolFactory.address);

      const deployData = defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        [...[this.weth.address, this.sushi.address].sort(), 30, true]
      );

      const INIT_CODE_HASH = keccak256(
        ["bytes"],
        [
          pack(
            ["bytes", "bytes"],
            [
              constantProductPoolBytecode,
              defaultAbiCoder.encode(["bytes", "address"], [deployData, this.masterDeployer.address]),
            ]
          ),
        ]
      );

      const computedConstantProductPoolAddress = getCreate2Address(
        this.constantProductPoolFactory.address,
        keccak256(["bytes"], [deployData]),
        INIT_CODE_HASH
      );

      await expect(this.masterDeployer.deployPool(this.constantProductPoolFactory.address, deployData))
        .to.emit(this.masterDeployer, "DeployPool")
        .withArgs(this.constantProductPoolFactory.address, computedConstantProductPoolAddress, deployData);
    });
  });

  describe("#addToWhiteList", async function () {
    it("Adds factory to whitelist", async function () {
      await this.masterDeployer.addToWhitelist(this.constantProductPoolFactory.address);
      expect(await this.masterDeployer.whitelistedFactories(this.constantProductPoolFactory.address)).to.be.true;
    });
  });

  describe("#removeFromWhitelist", async function () {
    it("Removes factory from whitelist", async function () {
      await this.masterDeployer.addToWhitelist(this.constantProductPoolFactory.address);
      await this.masterDeployer.removeFromWhitelist(this.constantProductPoolFactory.address);
      expect(await this.masterDeployer.whitelistedFactories(this.constantProductPoolFactory.address)).to.be.false;
    });
  });

  describe("#setFeeTo", async function () {
    it("Reverts on invalid fee", async function () {
      await expect(this.masterDeployer.setBarFee(MAX_FEE.add(1))).to.be.revertedWith("InvalidBarFee");
    });
    it("Mutates on valid fee", async function () {
      this.masterDeployer.setBarFee(0);
      expect(await this.masterDeployer.barFee()).to.equal(0);
    });
  });
});

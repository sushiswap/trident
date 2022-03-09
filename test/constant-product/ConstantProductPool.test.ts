import { expect } from "chai";
import { deployments, ethers } from "hardhat";

import type {
  BentoBoxV1,
  ConstantProductPool__factory,
  ERC20Mock,
  ERC20Mock__factory,
  FlashSwapMock,
  FlashSwapMock__factory,
  MasterDeployer,
} from "../../types";
import { initializedConstantProductPool, uninitializedConstantProductPool } from "../fixtures";

describe("Constant Product Pool", () => {
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
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", 30, false]
      );
      await expect(ConstantProductPool.deploy(deployData, masterDeployer.address)).to.be.revertedWith("ZERO_ADDRESS");
    });

    // TODO: fix instantiation allowed if token1 is zero
    it("deploys if token1 is zero", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000", 30, false]
      );
      await expect(ConstantProductPool.deploy(deployData, masterDeployer.address)).to.not.be.revertedWith(
        "ZERO_ADDRESS"
      );
    });

    it("reverts if token0 and token1 are identical", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000001", 30, false]
      );
      await expect(ConstantProductPool.deploy(deployData, masterDeployer.address)).to.be.revertedWith(
        "IDENTICAL_ADDRESSES"
      );
    });
    it("reverts if swap fee more than the max fee", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 10001, false]
      );
      await expect(ConstantProductPool.deploy(deployData, masterDeployer.address)).to.be.revertedWith(
        "INVALID_SWAP_FEE"
      );
    });
  });

  describe("#mint", function () {
    it("reverts if total supply is 0 and both token amounts are 0", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 30, false]
      );
      const constantProductPool = await ConstantProductPool.deploy(deployData, masterDeployer.address);
      await constantProductPool.deployed();
      const newLocal = "0x0000000000000000000000000000000000000003";
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [newLocal]);
      await expect(constantProductPool.mint(mintData)).to.be.revertedWith("INVALID_AMOUNTS");
    });

    it("reverts if insufficient liquidity minted", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      await token0.transfer(pool.address, 1);
      await token1.transfer(pool.address, 1);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await expect(pool.mint(mintData)).to.be.revertedWith("INSUFFICIENT_LIQUIDITY_MINTED");
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
      const pool = await uninitializedConstantProductPool();
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [await pool.token0(), "0x0000000000000000000000000000000000000000", false]
      );
      await expect(pool.swap(data)).to.be.revertedWith("POOL_UNINITIALIZED");
    });
  });

  describe("#flashSwap", function () {
    it("reverts on uninitialized", async () => {
      const pool = await uninitializedConstantProductPool();
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [await pool.token0(), "0x0000000000000000000000000000000000000000", false, 0, "0x"]
      );
      await expect(pool.flashSwap(data)).to.be.revertedWith("POOL_UNINITIALIZED");
    });

    it("reverts on invalid input token", async () => {
      const pool = await initializedConstantProductPool();
      const ERC20 = await ethers.getContractFactory<ERC20Mock__factory>("ERC20Mock");
      const token2 = await ERC20.deploy("Token 2", "TOKEN2", ethers.constants.MaxUint256);
      await token2.deployed();

      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token2.address, "0x0000000000000000000000000000000000000000", false, 0, "0x"]
      );

      await expect(pool.flashSwap(data)).to.be.revertedWith("INVALID_INPUT_TOKEN");
    });

    it("reverts on insuffiecient amount in token 0", async () => {
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [false, "0x0000000000000000000000000000000000000000", false]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token0.address, flashSwapMock.address, false, 1, flashSwapData]
      );

      await expect(flashSwapMock.testFlashSwap(pool.address, data)).to.be.revertedWith("INSUFFICIENT_AMOUNT_IN");
    });

    it("reverts on insuffiecient amount in token 1", async () => {
      const pool = await initializedConstantProductPool();
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [false, "0x0000000000000000000000000000000000000000", false]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token1.address, flashSwapMock.address, false, 1, flashSwapData]
      );

      await expect(flashSwapMock.testFlashSwap(pool.address, data)).to.be.revertedWith("INSUFFICIENT_AMOUNT_IN");
    });

    it("succeeds in flash swapping token 0 native", async () => {
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
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
      await flashSwapMock.testFlashSwap(pool.address, data);
    });

    it("succeeds in flash swapping token 0 bento", async () => {
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      await token0.transfer(bento.address, 100);
      await bento.deposit(token0.address, bento.address, flashSwapMock.address, 100, 0);

      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [true, token0.address, true]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token0.address, flashSwapMock.address, false, 100, flashSwapData]
      );
      await flashSwapMock.testFlashSwap(pool.address, data);
    });

    it("succeeds in flash swapping token 1 native", async () => {
      const pool = await initializedConstantProductPool();
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      await token1.transfer(flashSwapMock.address, 100);

      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [true, token1.address, false]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token1.address, flashSwapMock.address, true, 100, flashSwapData]
      );
      await flashSwapMock.testFlashSwap(pool.address, data);
    });

    it("succeeds in flash swapping token 1 bento", async () => {
      const pool = await initializedConstantProductPool();
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      await token1.transfer(bento.address, 100);
      await bento.deposit(token1.address, bento.address, flashSwapMock.address, 100, 0);

      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [true, token1.address, true]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token1.address, flashSwapMock.address, true, 100, flashSwapData]
      );
      await flashSwapMock.testFlashSwap(pool.address, data);
    });
  });

  describe("#poolIdentifier", function () {
    //
  });

  describe("#getAssets", function () {
    it("returns the assets the pool was deployed with, and in the correct order", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000002", "0x0000000000000000000000000000000000000001", 30, false]
      );
      const constantProductPool = await ConstantProductPool.deploy(deployData, masterDeployer.address);
      await constantProductPool.deployed();

      const assets = await constantProductPool.getAssets();

      await expect(assets[0], "0x0000000000000000000000000000000000000001");
      await expect(assets[1], "0x0000000000000000000000000000000000000002");
    });
  });

  describe("#updateBarFee", () => {
    it("mutates bar fee if changed on master deployer", async () => {
      const pool = await initializedConstantProductPool();

      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

      expect(await pool.barFee()).equal(0);

      await masterDeployer.setBarFee(10).then((tx) => tx.wait());

      expect(await masterDeployer.barFee()).equal(10);

      expect(await pool.barFee()).equal(0);

      await pool.updateBarFee().then((tx) => tx.wait());

      expect(await pool.barFee()).equal(10);

      // reset

      await masterDeployer.setBarFee(0).then((tx) => tx.wait());

      expect(await masterDeployer.barFee()).equal(0);

      await pool.updateBarFee().then((tx) => tx.wait());

      expect(await pool.barFee()).equal(0);
    });
  });

  describe("#getAmountOut", function () {
    it("returns 1000000000 given input of token0 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      const pool = await initializedConstantProductPool();
      const reserves = await pool.getReserves();
      expect(
        await pool.getAmountOut(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token0(), "1000000000"])
        )
      ).to.equal("999999999"); // 999999999
    });
    it("returns 999999999 given input of token1 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      const pool = await initializedConstantProductPool();
      const reserves = await pool.getReserves();
      expect(
        await pool.getAmountOut(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token1(), "1000000000"])
        )
      ).to.equal("999999999"); // 999999999
    });
    it("reverts if tokenIn is not equal to token0 and token1", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 30, false]
      );
      const constantProductPool = await ConstantProductPool.deploy(deployData, masterDeployer.address);
      await constantProductPool.deployed();
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256"],
        ["0x0000000000000000000000000000000000000003", 0]
      );
      await expect(constantProductPool.getAmountOut(data)).to.be.revertedWith("INVALID_INPUT_TOKEN");
    });
  });

  describe("#getAmountIn", function () {
    it("returns 1000000002 given output of token0 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      const pool = await initializedConstantProductPool();
      expect(
        await pool.getAmountIn(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token0(), "1000000000"])
        )
      ).to.equal("1000000002"); // 1000000002
    });

    it("returns 1000000000 given output of token1 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      const pool = await initializedConstantProductPool();
      expect(
        await pool.getAmountIn(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token1(), "1000000000"])
        )
      ).to.equal("1000000002"); // 1000000002
    });
    it("reverts if tokenOut is not equal to token 1 and token0", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 30, false]
      );
      const constantProductPool = await ConstantProductPool.deploy(deployData, masterDeployer.address);
      await constantProductPool.deployed();
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256"],
        ["0x0000000000000000000000000000000000000003", 0]
      );
      await expect(constantProductPool.getAmountIn(data)).to.be.revertedWith("INVALID_OUTPUT_TOKEN");
    });
  });

  describe("#getNativeReserves", function () {
    //
  });
});

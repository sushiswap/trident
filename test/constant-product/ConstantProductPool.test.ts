import { expect } from "chai";
import { deployments, ethers } from "hardhat";

import type { ConstantProductPool__factory, ERC20Mock, MasterDeployer } from "../../types";
import { initializedConstantProductPool, uninitializedConstantProductPool } from "../fixtures";

import { getBigNumber, randBetween } from "../utilities";
import { addLiquidity, addLiquidityInMultipleWays, burnLiquidity, initialize, swap } from "../harness/ConstantProduct";

describe("Constant Product Harness", function () {
  before(async () => {
    await initialize();
  });

  describe("#swap", () => {
    const maxHops = 3;
    it(`Should do ${maxHops * 8} types of swaps`, async () => {
      for (let i = 1; i <= maxHops; i++) {
        // We need to generate all permutations of [bool, bool, bool]. This loop goes from 0 to 7 and then
        // we use the binary representation of `j` to get the actual values. 0 in binary = false, 1 = true.
        // 000 -> false, false, false.
        // 010 -> false, true, false.
        for (let j = 0; j < 8; j++) {
          const binaryJ = j.toString(2).padStart(3, "0");
          // @ts-ignore
          await swap(i, getBigNumber(randBetween(1, 100)), binaryJ[0] == 1, binaryJ[1] == 1, binaryJ[2] == 1);
        }
      }
    });
  });

  describe("#mint", () => {
    it("Balanced liquidity to a balanced pool", async () => {
      const amount = getBigNumber(randBetween(10, 100));
      await addLiquidity(0, amount, amount);
    });
    it("Add liquidity in 16 different ways before swap fees", async () => {
      await addLiquidityInMultipleWays();
    });
    it("Add liquidity in 16 different ways after swap fees", async () => {
      await swap(2, getBigNumber(randBetween(100, 200)));
      await addLiquidityInMultipleWays();
    });
  });

  describe("#burn", () => {
    it(`Remove liquidity in 12 different ways`, async () => {
      for (let i = 0; i < 3; i++) {
        for (let j = 0; j < 2; j++) {
          // when fee is pending
          await burnLiquidity(0, getBigNumber(randBetween(5, 10)), i, j == 0);
          // when no fee is pending
          await burnLiquidity(0, getBigNumber(randBetween(5, 10)), i, j == 0);
          // generate fee
          await swap(2, getBigNumber(randBetween(100, 200)));
        }
      }
    });
  });
});

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
    it.skip("succeeds in flash swapping", async () => {
      //
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
      console.log({
        reserve0: reserves[0].toString(),
        reserve1: reserves[1].toString(),
      });
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

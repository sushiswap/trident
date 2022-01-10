import { deployments, ethers } from "hardhat";
import { ConstantProductPool__factory, MasterDeployer } from "../../types";
import { expect } from "chai";

describe("Constant Product Pool", () => {
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

import { initialize, addLiquidity, swap, burnLiquidity } from "../harness/ConstantProduct";
import { getBigNumber, randBetween, ZERO } from "../harness/helpers";

describe("Constant Product Pool", function () {
  before(async function () {
    await initialize();
  });

  beforeEach(async function () {
    //
  });

  describe("#swap", function () {
    const maxHops = 3;
    it(`Should do ${maxHops * 8} types of swaps`, async function () {
      for (let i = 1; i <= maxHops; i++) {
        // We need to generate all permutations of [bool, bool, bool]. This loop goes from 0 to 7 and then
        // we use the binary representation of `j` to get the actual values. 0 in binary = false, 1 = true.
        // 000 -> false, false, false.
        // 010 -> false, true, false.
        for (let j = 0; j < 8; j++) {
          const binaryJ = j.toString(2).padStart(3, "0");
          await swap(i, getBigNumber(randBetween(1, 100)), binaryJ[0] == 1, binaryJ[1] == 1, binaryJ[2] == 1);
        }
      }
    });
  });

  describe("#flashSwap", function () {
    //
  });

  describe("#mint", function () {
    it("Balanced liquidity to a balanced pool", async function () {
      const amount = getBigNumber(randBetween(10, 100));
      await addLiquidity(0, amount, amount);
    });
    it("Add liquidity in 16 different ways before swap fees", async function () {
      await addLiquidityInMultipleWays();
    });
    it("Add liquidity in 16 different ways after swap fees", async function () {
      await swap(2, getBigNumber(randBetween(100, 200)));
      await addLiquidityInMultipleWays();
    });
  });

  describe("#burn", function () {
    it(`Remove liquidity in 12 different ways`, async function () {
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

async function addLiquidityInMultipleWays() {
  // The first loop selects the liquidity amounts to add - [0, x], [x, 0], [x, x], [x, y]
  for (let i = 0; i < 4; i++) {
    const amount0 = i == 0 ? ZERO : getBigNumber(randBetween(10, 100));
    const amount1 = i == 1 ? ZERO : i == 2 ? amount0 : getBigNumber(randBetween(10, 100));

    // We need to generate all permutations of [bool, bool]. This loop goes from 0 to 3 and then
    // we use the binary representation of `j` to get the actual values. 0 in binary = false, 1 = true.
    // 00 -> false, false
    // 01 -> false, true
    for (let j = 0; j < 4; j++) {
      const binaryJ = parseInt(j.toString(2).padStart(2, "0"));
      await addLiquidity(0, amount0, amount1, binaryJ[0] == 1, binaryJ[1] == 1);
    }
  }
}

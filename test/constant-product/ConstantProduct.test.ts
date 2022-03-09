import { getBigNumber, randBetween } from "../utilities";
import { addLiquidity, addLiquidityInMultipleWays, burnLiquidity, initialize, swap } from "../harness/ConstantProduct";

describe("Constant Product", function () {
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

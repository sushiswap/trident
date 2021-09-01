// @ts-nocheck

import { initialize, addLiquidity, swap } from "./harness";
import { getBigNumber, randBetween, ZERO } from "./harness/helpers";

describe("Constant Product Pool", function () {
  before(async function () {
    await initialize();
  });

  describe("Add liquidity", function () {
    it("Balanced liquidity to a balanced pool", async function () {
      const amount = getBigNumber(randBetween(1, 100));
      await addLiquidity(0, amount, amount);
    });
    it("Unbalanced liquidity to a balanced pool", async function () {
      const amount0 = randBetween(1, 100);
      const amount1 = randBetween(101, 200);
      await addLiquidity(0, getBigNumber(amount0), getBigNumber(amount1));
    });
    it("Balanced liquidity to an unbalanced pool", async function () {
      const amount = getBigNumber(randBetween(1, 100));
      await addLiquidity(0, amount, amount);
    });
    it("Unbalanced liquidity to an unbalanced pool", async function () {
      const amount0 = randBetween(1, 100);
      const amount1 = randBetween(101, 200);
      await addLiquidity(0, getBigNumber(amount0), getBigNumber(amount1));
    });
    it("Using native token0", async function () {
      const amount0 = randBetween(1, 100);
      const amount1 = randBetween(101, 200);
      await addLiquidity(0, getBigNumber(amount0), getBigNumber(amount1), true);
    });
    it("Using native token1", async function () {
      const amount0 = randBetween(1, 100);
      const amount1 = randBetween(101, 200);
      await addLiquidity(
        0,
        getBigNumber(amount0),
        getBigNumber(amount1),
        false,
        true
      );
    });
    it("Using both tokens natively", async function () {
      const amount0 = randBetween(1, 100);
      const amount1 = randBetween(101, 200);
      await addLiquidity(
        0,
        getBigNumber(amount0),
        getBigNumber(amount1),
        true,
        true
      );
    });
    it("Using only token0", async function () {
      const amount = randBetween(1, 100);
      await addLiquidity(0, getBigNumber(amount), ZERO);
    });
    it("Using only token1", async function () {
      const amount = randBetween(1, 100);
      await addLiquidity(0, ZERO, getBigNumber(amount));
    });
  });

  describe("Swaps", function () {
    const maxHops = 2;
    it(`Should do ${maxHops * 8} types of swaps`, async function () {
      for (let i = 1; i <= maxHops; i++) {
        for (let j = 0; j < 8; j++) {
          const binaryJ = j.toString(2).padStart(3, "0");
          await swap(
            i,
            getBigNumber(randBetween(1, 100)),
            binaryJ[0] == 1,
            binaryJ[1] == 1,
            binaryJ[2] == 1
          );
        }
      }
    });
  });
});

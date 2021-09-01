// @ts-nocheck

import { initialize, addLiquidity } from "./harness";
import { getBigNumber } from "./harness/helpers";

describe("Router", function () {
  before(async function () {
    await initialize();
  });

  describe("Pool", function () {
    it("Should add balanced liquidity to a balanced pool", async function () {
      await addLiquidity(0, getBigNumber(100), getBigNumber(100));
    });
  });
});

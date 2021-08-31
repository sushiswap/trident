// @ts-nocheck

import { initialize } from "./harness";

describe("Router", function () {
  before(async function () {
    await initialize();
  });

  describe("Pool", function () {
    it("Should add liquidity directly to the pool", async function () {
      console.log("got here");
    });
  });
});

import { expect } from "chai";
import { BigNumber } from "ethers";
import seedrandom from "seedrandom";

import {
  convertRoute,
  createRoute,
  executeContractRouter,
  getABCTopoplogy,
  init,
} from "../helpers";
import { areCloseValues, getIntegerRandomValue } from "../utilities";

const testSeed = "2";
const rnd: () => number = seedrandom(testSeed);
const gasPrice = 1 * 200 * 1e-9;

describe("MultiPool Routing Tests", function () {
  // check normal values
  it("Should Test Normal Values", async function () {
    for (let i = 0; i < 1; ++i) {
      const signer = await init();

      const topology = await getABCTopoplogy();

      const fromToken = topology.tokens[0];
      const toToken = topology.tokens[2];
      const baseToken = topology.tokens[1];
      const [amountIn] = getIntegerRandomValue(17, rnd);

      const route = createRoute(
        fromToken,
        toToken,
        baseToken,
        topology,
        amountIn,
        gasPrice
      );

      const routerParams = convertRoute(route, signer.address);

      const amountOutPoolBN = await executeContractRouter(
        routerParams,
        toToken.address
      );

      // console.log("Expected amount out", route.amountOut.toString());
      // console.log("Actual amount out  ", amountOutPoolBN.toString());

      expect(
        areCloseValues(
          route.amountOut,
          parseInt(amountOutPoolBN.toString()),
          1e-14
        )
      ).to.equal(true, "predicted amount did not equal actual swapped amount");
    }
  });
});

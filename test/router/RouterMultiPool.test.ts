import { expect } from "chai";
import seedrandom from "seedrandom";

import {
  convertRoute,
  createRoute,
  executeContractRouter,
  getAB2VariantTopoplogy,
  getABCTopoplogy,
  init,
} from "../helpers";
import { areCloseValues, getIntegerRandomValue } from "../utilities";

const testSeed = "2";
const rnd: () => number = seedrandom(testSeed);
const gasPrice = 1 * 200 * 1e-9;

describe("MultiPool Routing Tests", function () {
  it("Should Test Normal Values with 1 Pool & 2 Pool variants", async function () {
    for (let i = 0; i < 1; ++i) {
      const signer = await init();

      const topology = await getAB2VariantTopoplogy(rnd);
      console.log("topology", topology);

      const fromToken = topology.tokens[0];
      const toToken = topology.tokens[1];
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
      console.log("route", route);

      const routerParams = convertRoute(route, signer.address, toToken.address);

      const amountOutPoolBN = await executeContractRouter(
        routerParams,
        toToken.address
      );

      console.log("Expected amount out", route.amountOut.toString());
      console.log("Actual amount out  ", amountOutPoolBN.toString());

      expect(
        areCloseValues(
          route.amountOut,
          parseInt(amountOutPoolBN.toString()),
          1e-14
        )
      ).to.equal(true, "predicted amount did not equal actual swapped amount");
    }
  });

  // check normal values
  it("Should Test Normal Values With 2 Pools & 1 Pool Variant", async function () {
    for (let i = 0; i < 1; ++i) {
      const signer = await init();

      const topology = await getABCTopoplogy(rnd);
      console.log("topology", topology);

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
      console.log("Route", route);

      const routerParams = convertRoute(route, signer.address, toToken.address);

      const amountOutPoolBN = await executeContractRouter(
        routerParams,
        toToken.address
      );

      console.log("Expected amount out", route.amountOut.toString());
      console.log("Actual amount out  ", amountOutPoolBN.toString());

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

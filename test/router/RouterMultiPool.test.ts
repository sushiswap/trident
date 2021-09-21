import { expect } from "chai";
import seedrandom from "seedrandom";

import {
  createRoute,
  executeComplexPath,
  getAB2VariantTopoplogy,
  getABCTopoplogy,
  init,
  getComplexPathParams,
  getAB3VariantTopoplogy,
  getABCDTopoplogy,
} from "../helpers";
import { areCloseValues, getIntegerRandomValue } from "../utilities";

const testSeed = "2";
const rnd: () => number = seedrandom(testSeed);
const gasPrice = 1 * 200 * 1e-9;

describe("MultiPool Routing Tests", function () {
  it("Should Test Normal Values With 3 Serial Pools", async function () {
    const signer = await init();

    const topology = await getABCDTopoplogy(rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[2];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, rnd);

    const route = createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      gasPrice
    );

    const routerParams = getComplexPathParams(
      route,
      signer.address,
      fromToken.address,
      toToken.address
    );

    const amountOutPoolBN = await executeComplexPath(
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
  });

  it("Should Test Normal Values with 3 Parallel Pools", async function () {
    const signer = await init();

    const topology = await getAB3VariantTopoplogy(rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[1];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, rnd);

    const route = createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      gasPrice
    );
    expect(route.legs.length).equal(3);

    const routerParams = getComplexPathParams(
      route,
      signer.address,
      fromToken.address,
      toToken.address
    );

    const amountOutPoolBN = await executeComplexPath(
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
  });

  it("Should Test Normal Values with 2 Parallel Pools", async function () {
    const signer = await init();

    const topology = await getAB2VariantTopoplogy(rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[1];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, rnd);

    const route = createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      gasPrice
    );
    expect(route.legs.length).equal(2);

    const routerParams = getComplexPathParams(
      route,
      signer.address,
      fromToken.address,
      toToken.address
    );

    const amountOutPoolBN = await executeComplexPath(
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
  });

  it("Should Test Normal Values With 2 Serial Pools", async function () {
    const signer = await init();

    const topology = await getABCTopoplogy(rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[2];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, rnd);

    const route = createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      gasPrice
    );

    const routerParams = getComplexPathParams(
      route,
      signer.address,
      fromToken.address,
      toToken.address
    );

    const amountOutPoolBN = await executeComplexPath(
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
  });
});

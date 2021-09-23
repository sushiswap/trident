import { expect } from "chai";
import seedrandom from "seedrandom";

import * as testHelper from "./helpers";
import { areCloseValues, getIntegerRandomValue } from "../utilities";
import { RouteType } from "./helpers/constants";

describe("MultiPool Routing Tests", function () {
  beforeEach(async function () {
    this.signer = await testHelper.init();
    this.gasPrice = 1 * 200 * 1e-9;
    this.rnd = seedrandom("2");
  });

  it("Should Test Normal Values with 3 Parallel Pools", async function () {
    const topology = await testHelper.getAB3VariantTopoplogy(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[1];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(30, this.rnd);

    const route = testHelper.createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      this.gasPrice
    );

    if (route == undefined) {
      throw "Failed to get route";
    }

    expect(route.legs.length).equal(3);

    const routerParams = testHelper.getTridentRouterParams(
      route,
      this.signer.address,
      fromToken.address,
      toToken.address
    );

    expect(routerParams.routeType).equal(RouteType.Complex);

    const amountOutPoolBN = await testHelper.executeTridentRoute(
      routerParams,
      toToken.address
    );

    expect(
      areCloseValues(
        route.amountOut,
        parseInt(amountOutPoolBN.toString()),
        1e-14
      )
    ).to.equal(true, "predicted amount did not equal actual swapped amount");
  });

  it("Should Test Normal Values with 2 Parallel Pools", async function () {
    const topology = await testHelper.getAB2VariantTopoplogy(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[1];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(30, this.rnd);

    const route = testHelper.createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      this.gasPrice
    );

    if (route == undefined) {
      throw "Failed to get route";
    }

    expect(route.legs.length).equal(2);

    const routerParams = testHelper.getTridentRouterParams(
      route,
      this.signer.address,
      fromToken.address,
      toToken.address
    );

    expect(routerParams.routeType).equal(RouteType.Complex);

    const amountOutPoolBN = await testHelper.executeTridentRoute(
      routerParams,
      toToken.address
    );

    expect(
      areCloseValues(
        route.amountOut,
        parseInt(amountOutPoolBN.toString()),
        1e-14
      )
    ).to.equal(true, "predicted amount did not equal actual swapped amount");
  });

  it("Should Test Normal Values With 2 Serial Pools", async function () {
    const topology = await testHelper.getABCTopoplogy(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[2];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, this.rnd);

    const route = testHelper.createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      this.gasPrice
    );

    if (route == undefined) {
      throw "Failed to get route";
    }

    const routerParams = testHelper.getTridentRouterParams(
      route,
      this.signer.address,
      fromToken.address,
      toToken.address
    );

    expect(routerParams.routeType).equal(RouteType.NonComplex);

    const amountOutPoolBN = await testHelper.executeTridentRoute(
      routerParams,
      toToken.address
    );

    expect(
      areCloseValues(
        route.amountOut,
        parseInt(amountOutPoolBN.toString()),
        1e-14
      )
    ).to.equal(true, "predicted amount did not equal actual swapped amount");
  });

  it("Should Test Normal Values With 3 Serial Pools", async function () {
    const topology = await testHelper.getABCDTopoplogy(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[2];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, this.rnd);

    const route = testHelper.createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      this.gasPrice
    );

    if (route == undefined) {
      throw "Failed to get route";
    }

    const routerParams = testHelper.getTridentRouterParams(
      route,
      this.signer.address,
      fromToken.address,
      toToken.address
    );

    expect(routerParams.routeType).equal(RouteType.NonComplex);

    const amountOutPoolBN = await testHelper.executeTridentRoute(
      routerParams,
      toToken.address
    );

    expect(
      areCloseValues(
        route.amountOut,
        parseInt(amountOutPoolBN.toString()),
        1e-14
      )
    ).to.equal(true, "predicted amount did not equal actual swapped amount");
  });

  it("Should Test Normal Values With 1 Pool", async function () {
    const topology = await testHelper.getSinglePool(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[1];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, this.rnd);

    const route = testHelper.createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      this.gasPrice
    );

    if (route == undefined) {
      throw "Failed to get route";
    }

    const routerParams = testHelper.getTridentRouterParams(
      route,
      this.signer.address,
      fromToken.address,
      toToken.address
    );

    expect(routerParams.routeType).equal(RouteType.Single);

    const amountOutPoolBN = await testHelper.executeTridentRoute(
      routerParams,
      toToken.address
    );

    expect(
      areCloseValues(
        route.amountOut,
        parseInt(amountOutPoolBN.toString()),
        1e-14
      )
    ).to.equal(true, "predicted amount did not equal actual swapped amount");
  });
});

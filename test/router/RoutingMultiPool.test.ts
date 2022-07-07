import { expect } from "chai";
import seedrandom from "seedrandom";
import { Contract } from "@ethersproject/contracts";
import { closeValues, RToken } from "@sushiswap/tines";
import * as testHelper from "./helpers";
import { getIntegerRandomValue, customError } from "../utilities";
import { RouteType, Topology } from "./helpers";

const rnd = seedrandom("0");

describe("MultiPool Routing Tests - Base Topologies", function () {
  beforeEach(async function () {
    [this.signer, this.tridentRouterAddress, this.bento, this.topologyFactory, this.swapParams] =
      await testHelper.init();
    this.gasPrice = 1 * 200 * 1e-9;
    this.rnd = rnd;
  });

  async function checkTokenBalancesAreZero(tokens: RToken[], bentoContract: Contract, tridentAddress: string) {
    for (let index = 0; index < tokens.length; index++) {
      const tokenBalance = await bentoContract.balanceOf(tokens[index].address, tridentAddress);
      expect(tokenBalance).equal(0);
    }
  }

  it("1 Pool Topology", async function () {
    const topology = await this.topologyFactory.getSinglePool(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[1];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, this.rnd);

    const route = testHelper.createRoute(fromToken, toToken, baseToken, topology, amountIn, this.gasPrice);

    if (route == undefined || route.status === "NoWay") {
      throw new Error("Tines failed to get route");
    }

    const routerParams = this.swapParams.getTridentRouterParams(
      route,
      this.signer.address,
      topology.pools,
      this.tridentRouterAddress
    );

    expect(routerParams.routeType).equal(RouteType.SinglePool);

    const amountOutPoolBN = await testHelper.executeTridentRoute(routerParams, toToken.address);

    await checkTokenBalancesAreZero(topology.tokens, this.bento, this.tridentRouterAddress);

    expect(closeValues(route.amountOut, parseInt(amountOutPoolBN.toString()), 1e-14)).to.equal(
      true,
      "predicted amount did not equal actual swapped amount"
    );
  });

  it("2 Serial Pools - revert due to slippage", async function () {
    const topology = await this.topologyFactory.getTwoSerialPools(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[2];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, this.rnd);

    const route = testHelper.createRoute(fromToken, toToken, baseToken, topology, amountIn, this.gasPrice);

    if (route == undefined || route.status === "NoWay") {
      throw new Error("Tines failed to get route");
    }

    route.amountOut = route.amountOut * (1 + 1 / 100);
    route.totalAmountOut = route.totalAmountOut * (1 + 1 / 100);

    const routerParams = this.swapParams.getTridentRouterParams(
      route,
      this.signer.address,
      topology.pools,
      this.tridentRouterAddress
    );

    expect(routerParams.routeType).equal(RouteType.SinglePath);

    await expect(testHelper.executeTridentRoute(routerParams, toToken.address)).to.be.revertedWith(
      customError("TooLittleReceived")
    );
  });

  it("4 Serial Pools Topology", async function () {
    const topology: Topology = await this.topologyFactory.getTopologySerial(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[4];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(20, this.rnd);

    const route = testHelper.createRoute(fromToken, toToken, baseToken, topology, amountIn, this.gasPrice);

    if (route == undefined || route.status === "NoWay") {
      throw new Error("Tines failed to get route");
    }

    expect(route.legs.length).equal(4);

    const routerParams = this.swapParams.getTridentRouterParams(
      route,
      this.signer.address,
      topology.pools,
      this.tridentRouterAddress
    );

    expect(routerParams.routeType).equal(RouteType.SinglePath);

    const amountOutPoolBN = await testHelper.executeTridentRoute(routerParams, toToken.address);

    await checkTokenBalancesAreZero(topology.tokens, this.bento, this.tridentRouterAddress);

    expect(closeValues(route.amountOut, parseInt(amountOutPoolBN.toString()), 1e-14)).to.equal(
      true,
      "predicted amount did not equal actual swapped amount"
    );
  });

  it("4 Parallel Pools Topology", async function () {
    const topology: Topology = await this.topologyFactory.getTopologyParallel(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[1];
    const baseToken = topology.tokens[1];
    //const [amountIn] = getIntegerRandomValue(26, this.rnd);
    const amountIn = 1e24;

    const route = testHelper.createRoute(fromToken, toToken, baseToken, topology, amountIn, this.gasPrice);
    if (route == undefined || route.status === "NoWay") {
      throw new Error("Tines failed to get route");
    }

    expect(route.legs.length).equal(4);

    const routerParams = this.swapParams.getTridentRouterParams(
      route,
      this.signer.address,
      topology.pools,
      this.tridentRouterAddress
    );

    expect(routerParams.routeType).equal(RouteType.ComplexPath);

    const amountOutPoolBN = await testHelper.executeTridentRoute(routerParams, toToken.address);

    await checkTokenBalancesAreZero(topology.tokens, this.bento, this.tridentRouterAddress);

    expect(closeValues(route.amountOut, parseInt(amountOutPoolBN.toString()), 1e-9)).to.equal(
      true,
      "predicted amount did not equal actual swapped amount"
    );
  });

  it("Bridge Topology", async function () {
    const topology = await this.topologyFactory.getFivePoolBridge(this.rnd);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[3];
    const baseToken = topology.tokens[2];

    const route = testHelper.createRoute(fromToken, toToken, baseToken, topology, 1000000, this.gasPrice);

    if (route == undefined || route.status === "NoWay") {
      throw new Error("Tines failed to get route");
    }

    expect(route.legs.length).equal(5);

    const routerParams = this.swapParams.getTridentRouterParams(
      route,
      this.signer.address,
      topology.pools,
      this.tridentRouterAddress
    );

    expect(routerParams.routeType).equal(RouteType.ComplexPath);

    const amountOutPoolBN = await testHelper.executeTridentRoute(routerParams, toToken.address);

    await checkTokenBalancesAreZero(topology.tokens, this.bento, this.tridentRouterAddress);

    expect(closeValues(route.amountOut, parseInt(amountOutPoolBN.toString()), 1e-14)).to.equal(
      true,
      "predicted amount did not equal actual swapped amount"
    );
  });
});

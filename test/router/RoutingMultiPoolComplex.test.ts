import { expect } from "chai";
import seedrandom from "seedrandom";
import { Contract } from "@ethersproject/contracts";

import { closeValues, getBigNumber, RouteStatus, RToken } from "@sushiswap/tines";

import * as testHelper from "./helpers";
import { getIntegerRandomValue } from "../utilities";
import { Topology, TridentRoute } from "./helpers";
import { TopologyFactory } from "./helpers/TopologyFactory";
import { TridentSwapParamsFactory } from "./helpers/TridentSwapParamsFactory";
import * as tines from "@sushiswap/tines";

let topologyFactory: TopologyFactory;
let swapParamsFactory: TridentSwapParamsFactory;
let bentoContract: Contract;
let tridentRouterAddress: string;

async function checkTokenBalancesAreZero(tokens: RToken[], bentoContract: Contract, tridentAddress: string) {
  for (let index = 0; index < tokens.length; index++) {
    const tokenBalance = await bentoContract.balanceOf(tokens[index].address, tridentAddress);
    expect(tokenBalance.toNumber()).equal(0);
  }
}

describe("MultiPool Routing Tests - Random Topologies & Random Swaps", function () {
  before(async function () {
    [this.signer, tridentRouterAddress, bentoContract, topologyFactory, swapParamsFactory] = await testHelper.init();
    this.gasPrice = 1 * 200 * 1e-9;
    this.rnd = seedrandom("7");
  });

  function getRandomTokens(rnd: () => number, topology: Topology): [RToken, RToken, RToken] {
    const num = topology.tokens.length;
    const token0 = Math.floor(rnd() * num);
    const token1 = (token0 + 1 + Math.floor(rnd() * (num - 1))) % num;
    expect(token0).not.equal(token1);
    const tokenBase = Math.floor(rnd() * num);

    return [topology.tokens[token0], topology.tokens[token1], topology.tokens[tokenBase]];
  }

  it("Random topology output prediction precision is ok", async function () {
    for (let index = 0; index < 10; index++) {
      // console.log(`Topology #${index}`);
      const topology = await topologyFactory.getRandomTopology(5, 0.3, this.rnd);

      for (let i = 0; i < 1; i++) {
        const [fromToken, toToken, baseToken] = getRandomTokens(this.rnd, topology);
        const [amountIn, amountInBn] = getIntegerRandomValue(21, this.rnd);
        const route = testHelper.createRoute(fromToken, toToken, baseToken, topology, amountIn, this.gasPrice);

        if (route == undefined) {
          throw new Error("Tines failed to find route");
        }

        if (route.status === RouteStatus.NoWay) {
          expect(route.amountOut).equal(0);
        } else {
          const routerParams: TridentRoute = swapParamsFactory.getTridentRouterParams(
            route,
            this.signer.address,
            topology.pools,
            tridentRouterAddress
          );

          expect(routerParams).to.not.be.undefined;

          let actualAmountOutBN = await testHelper.executeTridentRoute(routerParams, toToken.address);

          try {
            await checkTokenBalancesAreZero(topology.tokens, bentoContract, tridentRouterAddress);
          } catch (error) {
            console.log("Failed token balances check");
            throw error;
          }

          // console.log(topology);
          // console.log(`Test: ${index}, pools: ${topology.pools.length}, route legs: ${route.legs.length}, `
          //   + `from: ${fromToken.name}, to: ${toToken.name}`);
          // console.log(`Expected amount out: ${route.amountOut}`);
          // console.log(`Actual amount out: ${actualAmountOutBN.toString()}`);
          // console.log(`Precision: ${Math.abs(route.amountOut/parseInt(actualAmountOutBN.toString()) - 1)}`);

          expect(closeValues(route.amountOut, parseInt(actualAmountOutBN.toString()), route.legs.length * 1e-9)).to.equal(
            true,
            "predicted amount did not equal actual swapped amount"
          );

          await topologyFactory.refreshPools(topology);
        }
      }
    }
  });
});

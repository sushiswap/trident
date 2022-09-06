import { expect } from "chai";
import seedrandom from "seedrandom";
import { Contract } from "@ethersproject/contracts";
import { ConstantProductRPool, RouteStatus, RToken, StableSwapRPool } from "@sushiswap/tines";
import * as testHelper from "./helpers";
import { Topology, TridentRoute } from "./helpers";
import { TopologyFactory } from "./helpers/TopologyFactory";
import { TridentSwapParamsFactory } from "./helpers/TridentSwapParamsFactory";
import { BigNumberish } from "ethers";
import { Route } from "@sushiswap/core-sdk";

// temporary reduced because routes after Tines needed to be adapted for router
// 1. output should be rounded to integer values - critical for small output values
// 2. if swapPortion is very low - need to be rounded to integer values
const MINIMUM_EXPECTED_PRECISION = 1e-4;
const MINIMUM_SWAP_VALUE = 1e9;
const MAXIMUM_SWAP_VALUE = 1e21;

let topologyFactory: TopologyFactory;
let swapParamsFactory: TridentSwapParamsFactory;
let bentoContract: Contract;
let tridentRouterAddress: string;

function getRandom(rnd: () => number, min: number, max: number) {
  const minL = Math.log(min);
  const maxL = Math.log(max);
  const v = rnd() * (maxL - minL) + minL;
  const res = Math.exp(v);
  console.assert(res <= max && res >= min, "Random value is out of the range");
  return res;
}

async function checkTokenBalancesAreZero(tokens: RToken[], bentoContract: Contract, tridentAddress: string) {
  for (let index = 0; index < tokens.length; index++) {
    const tokenBalance = await bentoContract.balanceOf(tokens[index].address, tridentAddress);
    expect(tokenBalance.toNumber()).equal(0);
  }
}

function closeValues(a: number, b: number, accuracy: number, logInfoIfFalse = ""): boolean {
  if (accuracy === 0) return a === b;
  if (Math.abs(a) < 1 / accuracy) return Math.abs(a - b) <= 10;
  if (Math.abs(b) < 1 / accuracy) return Math.abs(a - b) <= 10;
  const res = Math.abs(a / b - 1) < accuracy;
  if (!res && logInfoIfFalse) {
    console.log("Expected close: ", a, b, accuracy, logInfoIfFalse);
    debugger;
  }
  return res;
}

function expectCloseValues(
  v1: BigNumberish,
  v2: BigNumberish,
  precision: number,
  description = "",
  additionalInfo = ""
) {
  const a = typeof v1 == "number" ? v1 : parseFloat(v1.toString());
  const b = typeof v2 == "number" ? v2 : parseFloat(v2.toString());
  const res = closeValues(a, b, precision);
  if (!res) {
    console.log(
      `Close values expectation failed:` +
        `\n v1 = ${a}` +
        `\n v2 = ${b}` +
        `\n precision = ${Math.abs(a / b - 1)}, expected < ${precision}` +
        `${additionalInfo == "" ? "" : "\n" + additionalInfo}`
    );
    debugger;
  }
  expect(res).to.equal(true, description);
  return res;
}

describe("MultiPool Routing Tests - Random Topologies & Random Swaps", function () {
  before(async function () {
    [this.signer, tridentRouterAddress, bentoContract, topologyFactory, swapParamsFactory] = await testHelper.init();
    this.gasPrice = 1 * 200 * 1e-9;
    this.rnd = seedrandom("0");
  });

  function getRandomTokens(rnd: () => number, topology: Topology): [RToken, RToken, RToken] {
    const num = topology.tokens.length;
    const token0 = Math.floor(rnd() * num);
    const token1 = (token0 + 1 + Math.floor(rnd() * (num - 1))) % num;
    expect(token0).not.equal(token1);
    const tokenBase = Math.floor(rnd() * num);

    return [topology.tokens[token0], topology.tokens[token1], topology.tokens[tokenBase]];
  }

  // TODO: To add CLPools
  it("Random topology output prediction precision is ok", async function () {
    for (let index = 0; index < 5; index++) {
      const topology = await topologyFactory.getRandomTopology(5, 0.4, this.rnd);

      for (let i = 0; i < 5; i++) {
        const [fromToken, toToken, baseToken] = getRandomTokens(this.rnd, topology);
        const amountIn = getRandom(this.rnd, MINIMUM_SWAP_VALUE, MAXIMUM_SWAP_VALUE);

        const route = testHelper.createRoute(fromToken, toToken, baseToken, topology, amountIn, this.gasPrice);

        if (route == undefined) {
          throw new Error("Tines failed to find route");
        }

        const minOut = route.legs.reduce((p, l) => Math.min(p, l.assumedAmountOut), 1e100);
        if (minOut < 100) continue; // tool small values for swapping - very rare for production

        // console.log(index, i, minOut, route?.legs.map(l => {
        //   const pool = topology.pools.find(p => p.address == l.poolAddress)
        //   if (pool instanceof ConstantProductRPool) return 'CP'
        //   if (pool instanceof StableSwapRPool) return 'SS'
        //   return '??'
        // }));
        // console.log(route?.legs.map(l => l.assumedAmountOut));
        // console.log(route.legs);

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

          let expectedPrecision = 0;
          route?.legs.forEach((l) => {
            const pool = topology.pools.find((p) => p.address == l.poolAddress);
            const granularity = l.tokenTo.address == pool?.token1.address ? pool?.granularity1() : pool?.granularity0();
            expectedPrecision += Math.max(MINIMUM_EXPECTED_PRECISION, ((granularity || 1) * 2) / l.assumedAmountOut);
          });
          //console.log(index, i, expectedPrecision);

          expectCloseValues(
            route.amountOut,
            parseInt(actualAmountOutBN.toString()),
            expectedPrecision,
            "predicted amount did not equal actual swapped amount"
          );

          await topologyFactory.refreshPools(topology);
        }
      }
    }
  });
});

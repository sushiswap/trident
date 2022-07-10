import { expect } from "chai";
import seedrandom from "seedrandom";
import { Contract } from "@ethersproject/contracts";
import { closeValues, RouteStatus, RToken } from "@sushiswap/tines";
import * as testHelper from "./helpers";
import { getIntegerRandomValue } from "../utilities";
import { Topology, TridentRoute } from "./helpers";
import { TopologyFactory } from "./helpers/TopologyFactory";
import { TridentSwapParamsFactory } from "./helpers/TridentSwapParamsFactory";
import { BigNumberish } from "ethers";

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

//const rnd = seedrandom("0");

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

  // Temp skip till the issue with amountIn won't be fixed in CLPool
  it("Random topology output prediction precision is ok", async function () {
    for (let index = 0; index < 5; index++) {
      const topology = await topologyFactory.getRandomTopology(5, 0.3, this.rnd);

      for (let i = 0; i < 5; i++) {
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

          expectCloseValues(
            route.amountOut,
            parseInt(actualAmountOutBN.toString()),
            route.legs.length * 1e-4,
            "predicted amount did not equal actual swapped amount"
          );

          await topologyFactory.refreshPools(topology);
        }
      }
    }
  });
});

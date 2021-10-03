import { expect } from "chai";
import seedrandom from "seedrandom";
import { Contract } from "@ethersproject/contracts";

import { closeValues, RouteStatus, RToken } from "@sushiswap/tines";

import * as testHelper from "./helpers";
import { getIntegerRandomValue } from "../utilities";
import { getRandomPools, getRandom, Topology, RouteType } from "./helpers";

const slippage = 1 - 0.5 / 100;

async function checkTokenBalancesAreZero(
  tokens: RToken[],
  bentoContract: Contract,
  tridentAddress: string
) {
  for (let index = 0; index < tokens.length; index++) {
    const tokenBalance = await bentoContract.balanceOf(
      tokens[index].address,
      tridentAddress
    );
    expect(tokenBalance).equal(0);
  }
}

describe("MultiPool Routing Tests - Random Topologies & Random Swaps", function () {
  before(async function () {
    [this.signer, this.tridentRouterAddress, this.bento] =
      await testHelper.init();
    this.gasPrice = 1 * 200 * 1e-9;
    this.rnd = seedrandom("2");
  });

  function getRandomTokens(
    rnd: () => number,
    topology: Topology
  ): [RToken, RToken, RToken] {
    const num = topology.tokens.length;
    const token0 = Math.floor(rnd() * num);
    const token1 = (token0 + 1 + Math.floor(rnd() * (num - 1))) % num;
    expect(token0).not.equal(token1);
    const tokenBase = Math.floor(rnd() * num);

    return [
      topology.tokens[token0],
      topology.tokens[token1],
      topology.tokens[tokenBase],
    ];
  }

  it("Should Test router with 10 random pools and 200 swaps", async function () {
    for (let index = 0; index < 35; index++) {
      const tokenCount = getRandom(this.rnd, 2, 20);
      const variants = getRandom(this.rnd, 1, 4);
      const topology = await getRandomPools(tokenCount, 1, this.rnd);

      for (let i = 0; i < 1; i++) {
        const [fromToken, toToken, baseToken] = getRandomTokens(
          this.rnd,
          topology
        );

        const [amountIn] = getIntegerRandomValue(20, this.rnd);

        // console.log("");
        // console.log(`Topology Iteration #${index}`);
        // console.log(`Swap #${i}`);
        // console.log(`Token Count #${tokenCount}`);
        // console.log("Before route execution");
        // let reserve0 = topology.pools[0].reserve0.toString();
        // let reserve1 = topology.pools[0].reserve1.toString();
        // console.log(`Reserve 0: ${reserve0}`);
        // console.log(`Reserve 1: ${reserve1}`);

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

        if (route.status === RouteStatus.NoWay) {
          expect(route.amountOut).equal(0);
        } else {
          const routerParams = testHelper.getTridentRouterParams(
            route,
            this.signer.address,
            this.tridentRouterAddress
          );

          expect(routerParams).to.not.be.undefined;

          let actualAmountOutBN;

          try {
            actualAmountOutBN = await testHelper.executeTridentRoute(
              routerParams,
              toToken.address
            );
          } catch (error) {
            console.log("");
            console.log("Swap Failed");
            console.log("");

            console.log("Error:");
            console.log(error);

            console.log(`Iteration: ${i}`);
            console.log(`Route:`);
            console.log(route);
            throw error;
          }

          try {
            await checkTokenBalancesAreZero(
              topology.tokens,
              this.bento,
              this.tridentRouterAddress
            );
          } catch (error) {
            console.log("Failed token balances check");
            throw error;
          }

          expect(
            closeValues(
              route.amountOut * slippage,
              parseInt(actualAmountOutBN.toString()),
              1e5
            )
          ).to.equal(
            true,
            "predicted amount did not equal actual swapped amount"
          );

          // console.log("After route execution");
          // reserve0 = topology.pools[0].reserve0.toString();
          // reserve1 = topology.pools[0].reserve1.toString();
          // console.log(`Reserve 0: ${reserve0}`);
          // console.log(`Reserve 1: ${reserve1}`);

          await testHelper.refreshPools(topology);
        }
      }
    }
  });
});

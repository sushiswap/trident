import { expect } from "chai";
import seedrandom from "seedrandom";
import { Contract } from "@ethersproject/contracts";

import { closeValues, RouteStatus, RToken } from "@sushiswap/tines";

import * as testHelper from "./helpers";
import { getIntegerRandomValue } from "../utilities";
import { getRandomPools, getRandom, Topology, RouteType } from "./helpers";

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

describe("MultiPool Routing Tests - Random Topology", function () {
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

  //Random1 - 200 random swaps back to back
  it("Should Test router with random pools 200 times", async function () {
    const topology = await getRandomPools(20, 1, this.rnd);

    for (let i = 0; i < 200; i++) {
      const [fromToken, toToken, baseToken] = getRandomTokens(
        this.rnd,
        topology
      );

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
        await checkTokenBalancesAreZero(
          topology.tokens,
          this.bento,
          this.tridentRouterAddress
        );

        const swapValuesAreClose = closeValues(
          route.amountOut,
          parseInt(actualAmountOutBN.toString()),
          1e-14
        );

        if (!swapValuesAreClose) {
          console.log(`Iteration #${i}`);
          console.log(`Expected output: ${route.amountOut.toString()}`);
          console.log(`Actual output: ${actualAmountOutBN.toString()}`);
          console.log(route);
        }

        expect(swapValuesAreClose).to.equal(
          true,
          "predicted amount did not equal actual swapped amount"
        );

        // expect(route.amountOut).lessThanOrEqual(
        //   parseInt(actualAmountOutBN.toString(), 1e-14),
        //   "predicted amount did not equal actual swapped amount"
        // );
      }
    }
  });
});

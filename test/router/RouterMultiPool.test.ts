import { expect } from "chai";
import { BigNumber } from "ethers";
import seedrandom from "seedrandom";

import { convertRoute, createRoute, getABCTopoplogy, init } from "../helpers";
import { areCloseValues, getIntegerRandomValue } from "../utilities";

const testSeed = "2";
const rnd: () => number = seedrandom(testSeed);
const gasPrice = 1 * 200 * 1e-9;

describe("MultiPool Routing Tests", function () {
  //Run Init

  // check normal values
  it("Should Test Normal Values", async function () {
    await init();

    const topology = await getABCTopoplogy();

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[2];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(17, rnd);

    const signer = topology.signer;
    const bento = topology.bento;
    const tridentRouter = topology.tridentRouter;

    const route = createRoute(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      gasPrice
    );

    const routerParams = convertRoute(route, signer.address);

    let outputBalanceBefore: BigNumber = await bento.balanceOf(
      toToken.address,
      signer.address
    );
    console.log("Output balance before", outputBalanceBefore.toString());

    await tridentRouter.connect(signer).complexPath(routerParams);

    let outputBalanceAfter: BigNumber = await bento.balanceOf(
      toToken.address,
      signer.address
    );
    console.log("Output balance after", outputBalanceAfter.toString());

    const amountOutPoolBN = outputBalanceAfter.sub(outputBalanceBefore);

    console.log("Expected amount out", route.amountOut.toString());
    console.log("Actual amount out", amountOutPoolBN.toString());

    expect(
      areCloseValues(
        route.amountOut,
        parseInt(amountOutPoolBN.toString()),
        1e-14
      )
    ).to.equal(true, "predicted amount did not equal actual swapped amount");
  });
});

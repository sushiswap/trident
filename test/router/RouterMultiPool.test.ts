import seedrandom from "seedrandom";

import {
  convertRoute,
  getRouteFromTopology,
  getTopoplogy,
  init,
} from "../helpers";
import { Topology } from "../helpers/helperInterfaces";
import { getIntegerRandomValue } from "../utilities";

const testSeed = "2"; // Change it to change random generator values
const rnd: () => number = seedrandom(testSeed); // random [0, 1)
const gasPrice = 1 * 200 * 1e-9;

describe("MultiPool Routing Tests", function () {
  //Run Init

  // check normal values
  it("Should Test Normal Values", async function () {
    await init();

    const topology = await getTopoplogy(rnd, 3);

    const fromToken = topology.tokens[0];
    const toToken = topology.tokens[2];
    const baseToken = topology.tokens[1];
    const [amountIn] = getIntegerRandomValue(17, rnd);

    const route = getRouteFromTopology(
      fromToken,
      toToken,
      baseToken,
      topology,
      amountIn,
      gasPrice
    );

    //const complexParams = getComplexPathParamsFromMultiRoute(route);
  });
});

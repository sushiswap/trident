import { getTopoplogy, init } from "../helpers";
import { Topology } from "../helpers/helperInterfaces";

describe("MultiPool Routing Tests", function () {
  //Run Init

  // check normal values
  it("Should Test Normal Values", async function () {
    const [, usdt, usdc, dai] = await init();
    const topology: Topology = await getTopoplogy([usdc, usdt, dai]);
  });
});

import { RToken, MultiRoute, findMultiRoute } from "@sushiswap/tines";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { BigNumber, Contract } from "ethers";

import { Topology, TridentRoute } from "./interfaces";
import { RouteType } from "./constants";
import { TridentPoolFactory } from "./TridentPoolFactory";
import { TestContext } from "./TestContext";
import { TopologyFactory } from "./TopologyFactory";

let alice: SignerWithAddress, feeTo: SignerWithAddress;

let testContext: TestContext;
let tridentPoolFactory: TridentPoolFactory;

export async function init(): Promise<[SignerWithAddress, string, Contract, TopologyFactory]> {
  testContext = new TestContext();
  await testContext.init();

  alice = testContext.Signer;
  feeTo = testContext.FeeTo;

  tridentPoolFactory = new TridentPoolFactory(alice, testContext.MasterDeployer, testContext.Bento);
  await tridentPoolFactory.init();

  const topologyFactory = new TopologyFactory(testContext.Erc20Factory, tridentPoolFactory, testContext.Bento, testContext.Signer);

  return [alice, testContext.TridentRouter.address, testContext.Bento, topologyFactory];
}

export function createRoute(
  fromToken: RToken,
  toToken: RToken,
  baseToken: RToken,
  topology: Topology,
  amountIn: number,
  gasPrice: number
): MultiRoute | undefined {
  const route = findMultiRoute(fromToken, toToken, amountIn, topology.pools, baseToken, gasPrice);
  return route;
}

export async function executeTridentRoute(tridentRouteParams: TridentRoute, toTokenAddress: string) {
  let outputBalanceBefore: BigNumber = await testContext.Bento.balanceOf(toTokenAddress, alice.address);

  const router = testContext.TridentRouter as Contract;

  try {
    switch (tridentRouteParams.routeType) {
      case RouteType.SinglePool:
        await (await router.connect(alice).exactInputSingle(tridentRouteParams)).wait();
        break;

      case RouteType.SinglePath:
        await (await router.connect(alice).exactInput(tridentRouteParams)).wait();
        break;

      case RouteType.ComplexPath:
      default:
        await (await router.connect(alice).complexPath(tridentRouteParams)).wait();
        break;
    }
  } catch (error) {
    throw error;
  }

  let outputBalanceAfter: BigNumber = await testContext.Bento.balanceOf(toTokenAddress, alice.address);

  return outputBalanceAfter.sub(outputBalanceBefore);
}

export * from "./RouterParams";
export * from "./random";
export * from "./interfaces";
export * from "./constants";

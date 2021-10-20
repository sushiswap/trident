import { RToken, MultiRoute, findMultiRoute } from "@sushiswap/tines";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { BigNumber, Contract } from "ethers";

import { Topology, TridentRoute } from "./Interfaces";
import { TridentPoolFactory } from "./TridentPoolFactory";
import { TestContext } from "./TestContext";
import { TopologyFactory } from "./TopologyFactory";
import { RouteType } from "./RouteType";
import { TridentSwapParamsFactory } from "./TridentSwapParamsFactory";

let alice: SignerWithAddress, feeTo: SignerWithAddress;

let ctx: TestContext;

export async function init(): Promise<[SignerWithAddress, string, Contract, TopologyFactory, TridentSwapParamsFactory]> {
  ctx = new TestContext();
  await ctx.init();

  alice = ctx.Signer;
  feeTo = ctx.FeeTo;

  const tridentPoolFactory = new TridentPoolFactory(alice, ctx.MasterDeployer, ctx.Bento, ctx.TridentRouter);
  await tridentPoolFactory.init();

  const topologyFactory = new TopologyFactory(ctx.Erc20Factory, tridentPoolFactory, ctx.Bento, ctx.Signer);
  const swapParams = new TridentSwapParamsFactory(tridentPoolFactory);

  return [alice, ctx.TridentRouter.address, ctx.Bento, topologyFactory, swapParams];
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
  let outputBalanceBefore: BigNumber = await ctx.Bento.balanceOf(toTokenAddress, alice.address);

  const router = ctx.TridentRouter as Contract;

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

  let outputBalanceAfter: BigNumber = await ctx.Bento.balanceOf(toTokenAddress, alice.address);

  return outputBalanceAfter.sub(outputBalanceBefore);
}

export * from "./random";
export * from "./RouteType";
export * from "./Interfaces";

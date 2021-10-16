import { ethers } from "hardhat";

import { CLRPool, ConstantProductRPool, getBigNumber, HybridRPool, MultiRoute, RPool } from "@sushiswap/tines";

import { RouteType } from "./RouteType";
import { ComplexPathParams, ExactInputParams, ExactInputSingleParams, InitialPath, Output, Path, PercentagePath } from "./interfaces";
import { BigNumber } from "@ethersproject/bignumber";

export function getTridentRouterParams(
  multiRoute: MultiRoute,
  senderAddress: string,
  pools: RPool[],
  tridentRouterAddress: string = "",
  slippagePercentage: number = 0.5
): ExactInputParams | ExactInputSingleParams | ComplexPathParams {
  const routeType = getRouteType(multiRoute);
  let routerParams;

  const slippage = 1 - slippagePercentage / 100;

  switch (routeType) {
    case RouteType.SinglePool:
      routerParams = getExactInputSingleParams(multiRoute, senderAddress, slippage, pools);
      break;

    case RouteType.SinglePath:
      routerParams = getExactInputParams(multiRoute, senderAddress, slippage, pools);
      break;

    case RouteType.ComplexPath:
    default:
      routerParams = getComplexPathParams(multiRoute, senderAddress, tridentRouterAddress, slippage, pools);
      break;
  }

  return routerParams;
}

function getExactInputSingleParams(
  multiRoute: MultiRoute,
  senderAddress: string,
  slippage: number,
  pools: RPool[]
): ExactInputSingleParams {
  return {
    amountIn: getBigNumber(multiRoute.amountIn * multiRoute.legs[0].absolutePortion),
    amountOutMinimum: getBigNumber(multiRoute.amountOut * slippage),
    tokenIn: multiRoute.legs[0].tokenFrom.address,
    pool: multiRoute.legs[0].poolAddress,
    data: ethers.utils.defaultAbiCoder.encode(["address", "address", "bool"], [multiRoute.legs[0].tokenFrom.address, senderAddress, false]),
    routeType: RouteType.SinglePool,
  };
}

function getExactInputParams(multiRoute: MultiRoute, senderAddress: string, slippage: number, pools: RPool[]): ExactInputParams {
  const routeLegs = multiRoute.legs.length;
  let paths: Path[] = [];

  for (let legIndex = 0; legIndex < routeLegs; ++legIndex) {
    const recipentAddress = isLastLeg(legIndex, multiRoute) ? senderAddress : multiRoute.legs[legIndex + 1].poolAddress;

    const pool = pools.find((p) => p.address === multiRoute.legs[legIndex].poolAddress);

    if (pool === undefined) {
      throw new Error(
        `An error occurred trying to get ExactInput params. Pool with address ${multiRoute.legs[legIndex].poolAddress} is not in topology.`
      );
    }

    const swapData = getSwapDataForPool(pool, multiRoute, legIndex, recipentAddress, false);

    if (multiRoute.legs[legIndex].tokenFrom.address === multiRoute.fromToken.address) {
      const path: Path = {
        pool: multiRoute.legs[legIndex].poolAddress,
        data: swapData,
      };
      paths.push(path);
    } else {
      const path: Path = {
        pool: multiRoute.legs[legIndex].poolAddress,
        data: swapData,
      };
      paths.push(path);
    }
  }

  let inputParams: ExactInputParams = {
    tokenIn: multiRoute.legs[0].tokenFrom.address,
    amountIn: getBigNumber(multiRoute.amountIn),
    amountOutMinimum: getBigNumber(multiRoute.amountOut * slippage),
    path: paths,
    routeType: RouteType.SinglePath,
  };

  return inputParams;
}

function getComplexPathParams(
  multiRoute: MultiRoute,
  senderAddress: string,
  tridentRouterAddress: string,
  slippage: number,
  pools: RPool[]
): ComplexPathParams {
  let initialPaths: InitialPath[] = [];
  let percentagePaths: PercentagePath[] = [];
  let outputs: Output[] = [];

  const routeLegs = multiRoute.legs.length;
  const initialPathCount = multiRoute.legs.filter((leg) => leg.tokenFrom.address === multiRoute.fromToken.address).length;

  const output: Output = {
    token: multiRoute.toToken.address,
    to: senderAddress,
    unwrapBento: false,
    minAmount: getBigNumber(multiRoute.amountOut * slippage),
  };
  outputs.push(output);

  for (let legIndex = 0; legIndex < routeLegs; ++legIndex) {
    const pool = pools.find((p) => p.address === multiRoute.legs[legIndex].poolAddress);

    if (pool === undefined) {
      throw new Error(
        `An error occurred trying to get ExactInput params. Pool with address ${multiRoute.legs[legIndex].poolAddress} is not in topology.`
      );
    }

    const swapData = getSwapDataForPool(pool, multiRoute, legIndex, tridentRouterAddress, false);

    if (multiRoute.legs[legIndex].tokenFrom.address === multiRoute.fromToken.address) {
      const initialPath: InitialPath = {
        tokenIn: multiRoute.legs[legIndex].tokenFrom.address,
        pool: multiRoute.legs[legIndex].poolAddress,
        amount: getInitialPathAmount(legIndex, multiRoute, initialPaths, initialPathCount),
        native: false,
        data: swapData,
      };

      initialPaths.push(initialPath);
    } else {
      const percentagePath: PercentagePath = {
        tokenIn: multiRoute.legs[legIndex].tokenFrom.address,
        pool: multiRoute.legs[legIndex].poolAddress,
        balancePercentage: getBigNumber(multiRoute.legs[legIndex].swapPortion * 10 ** 8),
        data: swapData,
      };
      percentagePaths.push(percentagePath);
    }
  }

  const complexParams: ComplexPathParams = {
    initialPath: initialPaths,
    percentagePath: percentagePaths,
    output: outputs,
    routeType: RouteType.ComplexPath,
  };

  return complexParams;
}

function isLastLeg(legIndex: number, multiRoute: MultiRoute): boolean {
  return legIndex === multiRoute.legs.length - 1;
}

function getRouteType(multiRoute: MultiRoute) {
  if (multiRoute.legs.length === 1) {
    return RouteType.SinglePool;
  }

  const routeInputTokens = multiRoute.legs.map(function (leg) {
    return leg.tokenFrom.address;
  });

  if (new Set(routeInputTokens).size === routeInputTokens.length) {
    return RouteType.SinglePath;
  }

  if (new Set(routeInputTokens).size !== routeInputTokens.length) {
    return RouteType.ComplexPath;
  }

  return "unknown";
}

function getInitialPathAmount(legIndex: number, multiRoute: MultiRoute, initialPaths: InitialPath[], initialPathCount: number): BigNumber {
  let amount;

  if (initialPathCount > 1 && legIndex === initialPathCount - 1) {
    const sumIntialPathAmounts = initialPaths
      .map((p) => p.amount)
      .reduce(function (a, b) {
        return a.add(b);
      });

    amount = getBigNumber(multiRoute.amountIn).sub(sumIntialPathAmounts);
  } else {
    amount = getBigNumber(multiRoute.amountIn * multiRoute.legs[legIndex].absolutePortion);
  }

  return amount;
}

function getSwapDataForPool(pool: RPool, multiRoute: MultiRoute, legIndex: number, recipent: string, unwrapBento: boolean): string {
  let data: string = "";
  const leg = multiRoute.legs[legIndex];

  if (pool instanceof HybridRPool || pool instanceof ConstantProductRPool) {
    data = ethers.utils.defaultAbiCoder.encode(["address", "address", "bool"], [leg.tokenFrom.address, recipent, unwrapBento]);
  } else if (pool instanceof CLRPool) {
    // (bool zeroForOne, uint256 inAmount, address recipient, bool unwrapBento)
    // TODO: zeroForOne ?

    //const clPool = new ConcentratedLiquidityPoolFactory().attach(pool.address);

    data = ethers.utils.defaultAbiCoder.encode(
      ["bool", "uint256", "address", "bool"],
      [true, getBigNumber(leg.assumedAmountIn), recipent, unwrapBento]
    );
  }

  return data;
}

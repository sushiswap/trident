import { ethers } from "hardhat";

import { getBigNumber, MultiRoute } from "@sushiswap/tines";

import { RouteType } from "./constants";
import {
  ComplexPathParams,
  ExactInputParams,
  ExactInputSingleParams,
  InitialPath,
  Output,
  Path,
  PercentagePath,
  TridentRoute,
} from "./interfaces";
import { BigNumber } from "@ethersproject/bignumber";

export function getTridentRouterParams(
  multiRoute: MultiRoute,
  senderAddress: string,
  tridentRouterAddress: string = "",
  slippagePercentage: number = 0.5
): ExactInputParams | ExactInputSingleParams | ComplexPathParams {
  const routeType = getRouteType(multiRoute);
  let routerParams;

  const slippage = 1 - slippagePercentage / 100;

  switch (routeType) {
    case RouteType.SinglePool:
      routerParams = getExactInputSingleParams(multiRoute, senderAddress, slippage);
      break;

    case RouteType.SinglePath:
      routerParams = getExactInputParams(multiRoute, senderAddress, slippage);
      break;

    case RouteType.ComplexPath:
    default:
      routerParams = getComplexPathParams(multiRoute, senderAddress, tridentRouterAddress, slippage);
      break;
  }

  return routerParams;
}

function getExactInputSingleParams(multiRoute: MultiRoute, senderAddress: string, slippage: number): ExactInputSingleParams {
  return {
    amountIn: getBigNumber(multiRoute.amountIn * multiRoute.legs[0].absolutePortion),
    amountOutMinimum: getBigNumber(multiRoute.amountOut * slippage),
    tokenIn: multiRoute.legs[0].tokenFrom.address,
    pool: multiRoute.legs[0].poolAddress,
    data: ethers.utils.defaultAbiCoder.encode(["address", "address", "bool"], [multiRoute.legs[0].tokenFrom.address, senderAddress, false]),
    routeType: RouteType.SinglePool,
  };
}

function getExactInputParams(multiRoute: MultiRoute, senderAddress: string, slippage: number): ExactInputParams {
  const routeLegs = multiRoute.legs.length;
  let paths: Path[] = [];

  for (let legIndex = 0; legIndex < routeLegs; ++legIndex) {
    const recipentAddress = isLastLeg(legIndex, multiRoute) ? senderAddress : multiRoute.legs[legIndex + 1].poolAddress;

    if (multiRoute.legs[legIndex].tokenFrom.address === multiRoute.fromToken.address) {
      const path: Path = {
        pool: multiRoute.legs[legIndex].poolAddress,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].tokenFrom.address, recipentAddress, false]
        ),
      };
      paths.push(path);
    } else {
      const path: Path = {
        pool: multiRoute.legs[legIndex].poolAddress,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].tokenFrom.address, recipentAddress, false]
        ),
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
  slippage: number
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
    if (multiRoute.legs[legIndex].tokenFrom.address === multiRoute.fromToken.address) {
      const initialPath: InitialPath = {
        tokenIn: multiRoute.legs[legIndex].tokenFrom.address,
        pool: multiRoute.legs[legIndex].poolAddress,
        amount: getInitialPathAmount(legIndex, multiRoute, initialPaths, initialPathCount),
        native: false,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].tokenFrom.address, tridentRouterAddress, false]
        ),
      };
      initialPaths.push(initialPath);
    } else {
      const percentagePath: PercentagePath = {
        tokenIn: multiRoute.legs[legIndex].tokenFrom.address,
        pool: multiRoute.legs[legIndex].poolAddress,
        balancePercentage: getBigNumber(multiRoute.legs[legIndex].swapPortion * 10 ** 8),
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [multiRoute.legs[legIndex].tokenFrom.address, tridentRouterAddress, false]
        ),
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

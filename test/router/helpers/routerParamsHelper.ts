import { ethers } from "hardhat";

import { getBigNumber, MultiRoute } from "@sushiswap/tines";

import { RouteType } from "./constants";
import { ComplexPathParams, ExactInputParams, ExactInputSingleParams, InitialPath, Output, Path, PercentagePath } from "./helperInterfaces";


export function getTridentRouterParams(multiRoute: MultiRoute, senderAddress: string, fromToken: string, toToken: string) {
    const routeType = getRouteType(multiRoute);
    let routerParams;
  
    switch (routeType) {
      case RouteType.Single:
        routerParams = getExactInputSingleParams(multiRoute, senderAddress);
        break;
  
      case RouteType.NonComplex:
        routerParams = getExactInputParams(multiRoute, senderAddress, fromToken, toToken);
        break;
  
      case RouteType.Complex:
      default:
        routerParams = getComplexPathParams(multiRoute, senderAddress, fromToken, toToken);
        break;
    }
    
    return routerParams;
}

function getRouteType(multiRoute: MultiRoute) { 
    if(multiRoute.legs.length === 1){
      return RouteType.Single;
    }
  
    const routeInputTokens = multiRoute.legs.map(function (leg) { return leg.token.address});
  
    if((new Set(routeInputTokens)).size === routeInputTokens.length){
      return RouteType.NonComplex;
    }
  
    if((new Set(routeInputTokens)).size !== routeInputTokens.length){
      return RouteType.Complex;
    }
  
    return "unknown";
}

function getRecipentAddress(multiRoute: MultiRoute, legIndex: number, fromTokenAddress: string, senderAddress: string): string {
    const isLastLeg = legIndex === multiRoute.legs.length - 1;
  
    if (isLastLeg || multiRoute.legs[legIndex + 1].token.address === fromTokenAddress) 
    {
      return senderAddress;
    } else 
    {
      return multiRoute.legs[legIndex + 1].address;
    }
}

function getExactInputSingleParams(multiRoute: MultiRoute, senderAddress: string) :ExactInputSingleParams {
    return {
        amountIn: getBigNumber(undefined, multiRoute.amountIn * multiRoute.legs[0].absolutePortion),
        amountOutMinimum: getBigNumber(undefined, 0),
        tokenIn: multiRoute.legs[0].token.address,
        pool: multiRoute.legs[0].address,
        data: ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [multiRoute.legs[0].token.address, senderAddress, false]
        ),
    }; 
}

function getExactInputParams(multiRoute: MultiRoute, senderAddress: string, fromToken: string, toToken: string) :ExactInputParams {
    const routeLegs = multiRoute.legs.length;
    let paths: Path[] = [];

    for (let legIndex = 0; legIndex < routeLegs; ++legIndex) {
        const recipentAddress = getRecipentAddress(
          multiRoute,
          legIndex,
          fromToken,
          senderAddress
        );
    
        if (multiRoute.legs[legIndex].token.address === fromToken) {
          const path: Path = { 
            pool: multiRoute.legs[legIndex].address,  
            data: ethers.utils.defaultAbiCoder.encode(
              ["address", "address", "bool"],
              [multiRoute.legs[legIndex].token.address, recipentAddress, false]
            ),
          };
          paths.push(path);

        } else 
        {
          const path: Path = { 
            pool: multiRoute.legs[legIndex].address, 
            data: ethers.utils.defaultAbiCoder.encode(
              ["address", "address", "bool"],
              [multiRoute.legs[legIndex].token.address, recipentAddress, false]
            ),
          };
          paths.push(path);
        }
      } 
  
    let inputParams: ExactInputParams = {
      tokenIn: multiRoute.legs[0].token.address,
      amountIn: getBigNumber(undefined, multiRoute.amountIn),
      amountOutMinimum: getBigNumber(undefined, 0),
      path: paths,
    };
  
    return inputParams;
}

export function getComplexPathParams(multiRoute: MultiRoute, senderAddress: string, fromToken: string, toToken: string ) {
    let initialPaths: InitialPath[] = [];
    let percentagePaths: PercentagePath[] = [];
    let outputs: Output[] = [];
  
    const output: Output = {
      token: toToken,
      to: senderAddress,
      unwrapBento: false,
      minAmount: getBigNumber(undefined, 0),
    };
    outputs.push(output);
  
    const routeLegs = multiRoute.legs.length;
  
    for (let legIndex = 0; legIndex < routeLegs; ++legIndex) {
      const recipentAddress = getRecipentAddress(
        multiRoute,
        legIndex,
        fromToken,
        senderAddress
      );
  
      if (multiRoute.legs[legIndex].token.address === fromToken) {
        const initialPath: InitialPath = {
          tokenIn: multiRoute.legs[legIndex].token.address,
          pool: multiRoute.legs[legIndex].address,
          amount: getBigNumber(
            undefined,
            multiRoute.amountIn * multiRoute.legs[legIndex].absolutePortion
          ),
          native: false,
          data: ethers.utils.defaultAbiCoder.encode(
            ["address", "address", "bool"],
            [multiRoute.legs[legIndex].token.address, recipentAddress, false]
          ),
        };
        initialPaths.push(initialPath);
      } else {
        const percentagePath: PercentagePath = {
          tokenIn: multiRoute.legs[legIndex].token.address,
          pool: multiRoute.legs[legIndex].address,
          balancePercentage: multiRoute.legs[legIndex].swapPortion * 1_000_000,
          data: ethers.utils.defaultAbiCoder.encode(
            ["address", "address", "bool"],
            [multiRoute.legs[legIndex].token.address, recipentAddress, false]
          ),
        };
        percentagePaths.push(percentagePath);
      }
    }
  
    const complexParams: ComplexPathParams = {
      initialPath: initialPaths,
      percentagePath: percentagePaths,
      output: outputs,
    };
  
    return complexParams;
  }
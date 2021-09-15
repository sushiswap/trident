import { BigNumber } from "ethers";
import { Pool } from "@sushiswap/sdk";
import { Contract } from "ethers";

export interface Path {
  pool: string;
  data: string;
}
export interface ExactInputParams {
  tokenIn: string;
  tokenOut: string;
  amountIn: BigNumber;
  amountOutMinimum: BigNumber;
  path: Path[];
}

export interface HybridPoolParams {
  A: number;
  fee: number;
  reserve0Exponent: number;
  reserve1Exponent: number;
  minLiquidity: number;
}

export interface ConstantProductPoolParams {
  fee: number;
  reserve0Exponent: number;
  reserve1Exponent: number;
  minLiquidity: number;
}

// Complex path types
export interface InitialPath {
  tokenIn: string;
  pool: string;
  native: boolean;
  amount: BigNumber;
  data: string;
}

export interface PercentagePath {
  tokenIn: string;
  pool: string;
  balancePercentage: number; // @dev Multiplied by 10^6.
  data: string;
}

export interface Output {
  token: string;
  to: string;
  unwrapBento: boolean;
  minAmount: BigNumber;
}

export interface ComplexPathParams {
  initialPath: InitialPath[];
  percentagePath: PercentagePath[];
  output: Output[];
}

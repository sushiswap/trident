import { BigNumber } from "ethers";

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

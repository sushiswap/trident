import { Pool } from "@sushiswap/sdk";
import { Contract } from "ethers";
import { RHybridPool, RConstantProductPool } from "@sushiswap/sdk";

export interface Topology {
  tokens: Map<string, Contract>;
  prices: TokenPrice[];
  hybridPools: RHybridPool[];
  constantPools: RConstantProductPool[];
}

export interface HPoolParams {
  A: number;
  fee: number;
  reserveAExponent: number;
  reserveBExponent: number;
  minLiquidity: number;
  TokenA: Contract;
  TokenB: Contract;
}

export interface CPoolParams {
  fee: number;
  reserveAExponent: number;
  reserveBExponent: number;
  minLiquidity: number;
  TokenA: Contract;
  TokenB: Contract;
}

export interface TokenPrice {
  name: string;
  address: string;
  price: number;
}

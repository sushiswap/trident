import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Pool, RToken } from "@sushiswap/sdk";
import { BigNumber, Contract, ContractFactory } from "ethers";

export interface TestContracts { 
  signer: SignerWithAddress;
  bentoContract: Contract,
  tridentRouter: Contract
}
 
export interface Topology {
  tokens: RToken[];
  prices: number[];
  pools: Pool[];
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
  
export interface Variants {
  [key: string]: number
}

export interface PoolDeploymentContracts {
  hybridPoolFactory: ContractFactory,
  hybridPoolContract: Contract,
  constPoolFactory: ContractFactory, 
  constantPoolContract: Contract, 
  masterDeployerContract: Contract,
  bentoContract: Contract,
  account: SignerWithAddress
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

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Pool, RToken } from "@sushiswap/sdk";
import { BigNumber, Contract, ContractFactory } from "ethers";
 
export interface Topology {
  tokens: RToken[];
  prices: number[];
  pools: Pool[];
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
  balancePercentage: number;
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
import { deployments } from "hardhat";
import { ERC20Mock__factory } from "../../types";
import { getBigNumber } from "../utilities";

const N = 10;

export const initializeTokens = deployments.createFixture(async ({ ethers }) => {
  const ERC20 = await ethers.getContractFactory<ERC20Mock__factory>("ERC20Mock");
  return Promise.all([...Array(N).keys()].map((n) => ERC20.deploy(`Token ${n}`, `TOKEN${n}`, getBigNumber(1000000))));
}, "initializeTokens");

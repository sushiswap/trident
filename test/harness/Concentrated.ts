// @ts-nocheck

import { ethers } from "hardhat";
import { getBigNumber } from "./helpers";

export async function initialize() {
  const ERC20 = await ethers.getContractFactory("ERC20Mock");
  const Bento = await ethers.getContractFactory("BentoBoxV1");
  const Deployer = await ethers.getContractFactory("MasterDeployer");
  const PoolFactory = await ethers.getContractFactory("ConcentratedProductPoolFactory");
  const TridentRouter = await ethers.getContractFactory("TridentRouter");
  const Pool = await ethers.getContractFactory("ConcentratedProductPool");

  let tokens = await Promise.all(Array(10).fill(ERC20.deploy("Token", "TOK", getBigNumber(1000000))));
}

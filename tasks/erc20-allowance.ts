import type { ERC20Mock } from "../types";
import { task } from "hardhat/config";

task("erc20-allownace", "ERC20 allowance")
  .addParam("token", "Token")
  .addParam("owner", "Owner")
  .addParam("spender", "Spender")
  .setAction(async ({ token, owner, spender }, { ethers }, runSuper) => {
    const erc20 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", token);
    return erc20.allowance(owner, spender);
  });

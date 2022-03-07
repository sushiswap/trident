import { BENTOBOX_ADDRESS } from "@sushiswap/core-sdk";
import type { MasterDeployer } from "../types";
import { task } from "hardhat/config";

task("whitelist-factory", "Whitelist Router on BentoBox").setAction(async function (_, { ethers, getChainId }) {
  const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

  const constantProductPoolFactory = await ethers.getContract<MasterDeployer>("ConstantProductPoolFactory");

  if (!(await masterDeployer.whitelistedFactories(constantProductPoolFactory.address))) {
    await masterDeployer.addToWhitelist(constantProductPoolFactory.address);
    console.log("added cpp factory");
  }
});

import { ChainId, DAI_ADDRESS, USDC_ADDRESS, WETH9_ADDRESS } from "@sushiswap/core-sdk";
import { task, types } from "hardhat/config";

import type { MasterDeployer } from "../types";

task("stable-verify", "Stable Pool verify")
  .addParam("address", "Pool address")
  .setAction(async function ({ address }, { ethers, run }) {
    console.log(`Verify stable pool: ${address}`);
    await run("verify:verify", {
      address,
      constructorArguments: [],
    });
  });

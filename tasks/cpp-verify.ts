import { ChainId, USDC_ADDRESS, WETH9_ADDRESS } from "@sushiswap/core-sdk";
import { task, types } from "hardhat/config";

import type { MasterDeployer } from "../types";

task("cpp-verify", "Constant Product Pool verify")
  .addOptionalParam(
    "tokenA",
    "Token A",
    WETH9_ADDRESS[ChainId.KOVAN], // kovan weth
    types.string
  )
  .addOptionalParam(
    "tokenB",
    "Token B",
    USDC_ADDRESS[ChainId.KOVAN], // kovan dai
    types.string
  )
  .addOptionalParam("fee", "Fee tier", 30, types.int)
  .addOptionalParam("twap", "Twap enabled", true, types.boolean)
  .setAction(async function ({ tokenA, tokenB, fee, twap }, { ethers, run }) {
    console.log(`Verify cpp tokenA: ${tokenA} tokenB: ${tokenB} fee: ${fee} twap: ${twap}`);

    const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

    const address = await run("cpp-address", { tokenA, tokenB, fee, twap });

    console.log(`Verify cpp ${address}`);

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256", "bool"],
      [...[tokenA, tokenB].sort(), fee, twap]
    );

    await run("verify:verify", {
      address,
      constructorArguments: [deployData, masterDeployer.address],
    });
  });

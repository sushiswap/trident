import { DAI_ADDRESS, USDC_ADDRESS, USDT_ADDRESS, WNATIVE_ADDRESS } from "@sushiswap/core-sdk";
import { task, types } from "hardhat/config";

task("cpp-stable-pools", "Generate stable pool addresses")
  .addOptionalParam("fee", "Fee tier", 30, types.int)
  .addOptionalParam("twap", "Twap enabled", true, types.boolean)
  .setAction(async function ({ fee, twap }, { ethers, run, getChainId }) {
    const chainId = await getChainId();

    const wnative = WNATIVE_ADDRESS[chainId];
    const usdc = USDC_ADDRESS[chainId];
    const dai = DAI_ADDRESS[chainId];
    const usdt = USDT_ADDRESS[chainId];

    for (const [tokenA, tokenB] of [
      [wnative, usdc],
      [wnative, usdt],
      [wnative, dai],
    ]) {
      console.log(`Genrating pool for tokenA: ${tokenA} and ${tokenB}`);
      const address = await run("cpp-address", { tokenA, tokenB, fee, twap });
      console.log(`Genrated address ${address} pool with tokenA: ${tokenA} and ${tokenB}`);
    }
  });

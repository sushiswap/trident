import { ChainId, WETH9_ADDRESS, USDC_ADDRESS, WNATIVE_ADDRESS } from "@sushiswap/core-sdk";
import { task, types } from "hardhat/config";
import { ConstantProductPoolFactory, MasterDeployer } from "../types";

task("cpp-deploy", "Constant Product Pool deploy")
  .addOptionalParam(
    "tokenA",
    "Token A",
    WNATIVE_ADDRESS[ChainId.MATIC], // kovan weth
    types.string
  )
  .addOptionalParam(
    "tokenB",
    "Token B",
    USDC_ADDRESS[ChainId.MATIC], // kovan dai
    types.string
  )
  .addOptionalParam("fee", "Fee tier", 30, types.int)
  .addOptionalParam("twap", "Twap enabled", true, types.boolean)
  .addOptionalParam("verify", "Verify", true, types.boolean)
  .setAction(async function ({ tokenA, tokenB, fee, twap, verify }, { ethers, run }) {
    const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

    const constantProductPoolFactory = await ethers.getContract<ConstantProductPoolFactory>(
      "ConstantProductPoolFactory"
    );

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256", "bool"],
      [...[tokenA, tokenB].sort(), fee, twap]
    );

    console.log([...[tokenA, tokenB].sort(), fee, twap], {
      factory: constantProductPoolFactory.address,
      deployData,
    });

    // console.log("1", [...[tokenA, tokenB].sort(), fee, twap]);
    // const contractTransaction = await masterDeployer.deployPool(constantProductPoolFactory.address, deployData);
    // console.log("2");
    // if (!verify) return;

    // const contractReceipt = await contractTransaction.wait(5);

    // const { events } = contractReceipt;

    // await run("verify:verify", {
    //   address: events?.[0].args?.pool,
    //   constructorArguments: [deployData, masterDeployer.address],
    // });
  });

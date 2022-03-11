import { ChainId, USDC_ADDRESS, WETH9_ADDRESS, WNATIVE_ADDRESS } from "@sushiswap/core-sdk";
import { task, types } from "hardhat/config";

task("cpp-address", "Constant Product Pool deploy")
  .addOptionalParam("tokenA", "Token A", WNATIVE_ADDRESS[ChainId.MATIC], types.string)
  .addOptionalParam("tokenB", "Token B", USDC_ADDRESS[ChainId.MATIC], types.string)
  .addOptionalParam("fee", "Fee tier", 30, types.int)
  .addOptionalParam("twap", "Twap enabled", true, types.boolean)
  .setAction(async ({ tokenA, tokenB, fee, twap }, { ethers }): Promise<string> => {
    const master = (await ethers.getContract("MasterDeployer")).address;
    const factory = (await ethers.getContract("ConstantProductPoolFactory")).address;
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256", "bool"],
      [...[tokenA, tokenB].sort(), fee, twap]
    );
    const salt = ethers.utils.keccak256(deployData);
    const constructorParams = ethers.utils.defaultAbiCoder
      .encode(["bytes", "address"], [deployData, master])
      .substring(2);
    const Pool = await ethers.getContractFactory("ConstantProductPool");
    const initCodeHash = ethers.utils.keccak256(Pool.bytecode + constructorParams);
    const address = ethers.utils.getCreate2Address(factory, salt, initCodeHash);
    console.log(address, [...[tokenA, tokenB].sort(), fee, twap]);
    return address;
  });

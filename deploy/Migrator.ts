import { BENTOBOX_ADDRESS, ChainId, WNATIVE } from "@sushiswap/core-sdk";

import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({ ethers, deployments, getNamedAccounts, getChainId }: HardhatRuntimeEnvironment) {
  console.log("Running TridentSushiRollCP deploy script");
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = Number(await getChainId());

  let bentoBoxV1Address;

  if (chainId === 31337) {
    // for testing purposes we use a redeployed bentobox address
    bentoBoxV1Address = (await ethers.getContract("BentoBoxV1")).address;
  } else {
    if (!(chainId in WNATIVE)) {
      throw Error(`No WETH on chain #${chainId}!`);
    } else if (!(chainId in BENTOBOX_ADDRESS)) {
      throw Error(`No BENTOBOX on chain #${chainId}!`);
    }
    bentoBoxV1Address = BENTOBOX_ADDRESS[chainId as ChainId];
  }

  const constantProductPoolFactoryAddress = (await ethers.getContract("ConstantProductPoolFactory")).address;
  const masterDeployerAddress = (await ethers.getContract("MasterDeployer")).address;

  const { address } = await deploy("TridentSushiRollCP", {
    from: deployer,
    args: [bentoBoxV1Address, constantProductPoolFactoryAddress, masterDeployerAddress],
    deterministicDeployment: false,
  });

  console.log("TridentSushiRollCP deployed at ", address);
};

export default deployFunction;

deployFunction.dependencies = ["ConstantProductPoolFactory"];

deployFunction.tags = ["TridentSushiRollCP"];

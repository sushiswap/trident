import { BENTOBOX_ADDRESS, ChainId, WNATIVE } from "@sushiswap/sdk";

import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  ethers,
  deployments,
  getNamedAccounts,
  getChainId,
}: HardhatRuntimeEnvironment) {
  console.log("Running BentoBox deploy script");
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const { address } = await deploy("BentoBoxV1", {
    from: deployer,
    args: ["0xd0a1e359811322d97991e03f863a0c30c2cf029c"],
    deterministicDeployment: false,
  });

  console.log("BentoBoxV1 deployed at ", address);
};

export default deployFunction;

deployFunction.tags = ["BentoBox"];

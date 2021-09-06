import { BENTOBOX_ADDRESS, ChainId, WNATIVE } from "@sushiswap/sdk";

import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  ethers,
  deployments,
  getNamedAccounts,
  getChainId,
}: HardhatRuntimeEnvironment) {
  console.log("Running TridentRouter deploy script");
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = Number(await getChainId());

  const bentoBoxV1 = await ethers.getContract("BentoBoxV1");

  const { address } = await deploy("TridentRouter", {
    from: deployer,
    args: [bentoBoxV1.address, "0xd0a1e359811322d97991e03f863a0c30c2cf029c"],
    deterministicDeployment: false,
  });

  console.log("TridentRouter deployed at ", address);
};

export default deployFunction;

deployFunction.dependencies = ["MasterDeployer"];

deployFunction.tags = ["TridentRouter"];

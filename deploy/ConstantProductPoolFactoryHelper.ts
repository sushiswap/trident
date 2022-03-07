import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
  ethers,
  run,
}: HardhatRuntimeEnvironment) {
  // console.log("Running ConstantProductPoolFactoryHelper deploy script");
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const { address, newlyDeployed } = await deploy("ConstantProductPoolFactoryHelper", {
    from: deployer,
    deterministicDeployment: false,
    waitConfirmations: process.env.VERIFY_ON_DEPLOY === "true" ? 5 : undefined,
  });

  if (newlyDeployed && process.env.VERIFY_ON_DEPLOY === "true") {
    await run("verify:verify", {
      address,
    });
  }
  // console.log("ConstantProductPoolFactoryHelper deployed at ", address);
};

export default deployFunction;

deployFunction.tags = ["ConstantProductPoolFactoryHelper"];

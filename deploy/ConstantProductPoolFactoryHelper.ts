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
    waitConfirmations: 5,
  });

  if (newlyDeployed) {
    await run("verify:verify", {
      address,
    });
  }
  // console.log("ConstantProductPoolFactoryHelper deployed at ", address);
};

export default deployFunction;

deployFunction.tags = ["ConstantProductPoolFactoryHelper"];

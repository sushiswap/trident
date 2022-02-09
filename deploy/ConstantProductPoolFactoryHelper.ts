import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
  ethers,
}: HardhatRuntimeEnvironment) {
  // console.log("Running ConstantProductPoolFactoryHelper deploy script");
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const { address } = await deploy("ConstantProductPoolFactoryHelper", {
    from: deployer,
    deterministicDeployment: false,
    args: [],
  });

  // console.log("ConstantProductPoolFactoryHelper deployed at ", address);
};

export default deployFunction;

deployFunction.tags = ["ConstantProductPoolFactoryHelper"];

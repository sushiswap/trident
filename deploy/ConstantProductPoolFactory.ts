import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
  ethers,
  run,
  getChainId,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const masterDeployer = await ethers.getContract("MasterDeployer");

  const { address, newlyDeployed } = await deploy("ConstantProductPoolFactory", {
    from: deployer,
    deterministicDeployment: false,
    args: [masterDeployer.address],
    waitConfirmations: process.env.VERIFY_ON_DEPLOY === "true" ? 5 : undefined,
  });

  if (!(await masterDeployer.whitelistedFactories(address))) {
    console.debug("Add ConstantProductPoolFactory to MasterDeployer whitelist");
    await (await masterDeployer.addToWhitelist(address)).wait();
  }

  if (newlyDeployed && process.env.VERIFY_ON_DEPLOY === "true") {
    await run("verify:verify", {
      address,
      constructorArguments: [masterDeployer.address],
    });
  }
};

export default deployFunction;

deployFunction.dependencies = ["MasterDeployer"];

deployFunction.tags = ["ConstantProductPoolFactory"];

import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
  ethers,
  run,
}: HardhatRuntimeEnvironment) {
  // console.log("Running IndexPoolFactory deploy script");
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();
  const masterDeployer = await ethers.getContract("MasterDeployer");

  const { address, newlyDeployed } = await deploy("IndexPoolFactory", {
    from: deployer,
    deterministicDeployment: false,
    args: [masterDeployer.address],
    waitConfirmations: process.env.VERIFY_ON_DEPLOY === "true" ? 5 : undefined,
  });

  if (!(await masterDeployer.whitelistedFactories(address))) {
    // console.log("Add IndexPoolFactory to MasterDeployer whitelist");
    await (await masterDeployer.addToWhitelist(address)).wait();
  }

  if (newlyDeployed && process.env.VERIFY_ON_DEPLOY === "true") {
    await run("verify:verify", {
      address,
      constructorArguments: [masterDeployer.address],
    });
  }

  // console.log("IndexPoolFactory deployed at ", address);
};

export default deployFunction;

deployFunction.dependencies = ["MasterDeployer"];

deployFunction.tags = ["IndexPoolFactory"];

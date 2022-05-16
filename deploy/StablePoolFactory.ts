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

  const { address, newlyDeployed } = await deploy("StablePoolFactory", {
    from: deployer,
    deterministicDeployment: false,
    args: [masterDeployer.address],
    waitConfirmations: process.env.VERIFY_ON_DEPLOY === "true" ? 10 : undefined,
  });

  if (!(await masterDeployer.whitelistedFactories(address))) {
    //console.debug("Add StablePoolFactory to MasterDeployer whitelist");
    await (await masterDeployer.addToWhitelist(address)).wait();
  }

  const { address: addrToken0 } = await deploy("Token0", {
    contract: "ERC20",
    //from: deployer,
    //deterministicDeployment: false,
    args: ["Token 0", "TOKEN0", ethers.constants.MaxUint256],
    //waitConfirmations: process.env.VERIFY_ON_DEPLOY === "true" ? 10 : undefined,
  });

  if (newlyDeployed && process.env.VERIFY_ON_DEPLOY === "true") {
    try {
      await run("verify:verify", {
        address,
        constructorArguments: [masterDeployer.address],
      });
    } catch (error) {
      console.error(error);
    }
  }
};

export default deployFunction;

deployFunction.dependencies = ["MasterDeployer"];

deployFunction.tags = ["StablePoolFactory"];

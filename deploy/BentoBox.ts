import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  ethers,
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  console.log("Running BentoBox deploy script");

  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const weth9 = await deploy("WETH9", {
    from: deployer,
    args: [],
    deterministicDeployment: false,
  });

  const { address } = await deploy("BentoBoxV1", {
    from: deployer,
    args: [weth9.address],
    deterministicDeployment: false,
  });

  console.log("BentoBoxV1 deployed at ", address);
};

export default deployFunction;

deployFunction.tags = ["BentoBoxV1"];

deployFunction.skip = ({ getChainId }) =>
  new Promise(async (resolve, reject) => {
    try {
      const chainId = await getChainId();
      console.log("CHAINID", chainId);
      resolve(chainId !== "31337");
    } catch (error) {
      reject(error);
    }
  });

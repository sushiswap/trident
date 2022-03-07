import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { WETH9 } from "../types";

const deployFunction: DeployFunction = async function ({
  ethers,
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  console.log("Running WETH9 deploy script");

  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("WETH9", {
    from: deployer,
    deterministicDeployment: false,
  });

  const weth9 = await ethers.getContract<WETH9>("WETH9");
  await weth9.deposit({ value: 100 });

  console.log("WETH9 deployed at ", weth9.address);
};

export default deployFunction;

deployFunction.tags = ["WETH9"];

deployFunction.skip = ({ getChainId }) =>
  new Promise(async (resolve, reject) => {
    try {
      const chainId = await getChainId();
      resolve(chainId !== "31337");
    } catch (error) {
      reject(error);
    }
  });

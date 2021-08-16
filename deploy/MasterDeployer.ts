import { BENTOBOX_ADDRESS, ChainId, WNATIVE } from "@sushiswap/sdk";

import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  ethers,
  deployments,
  getNamedAccounts,
  getChainId,
}: HardhatRuntimeEnvironment) {
  console.log("Running MasterDeployer deploy script");
  const { deploy } = deployments;

  const { deployer, feeTo } = await getNamedAccounts();

  const chainId = Number(await getChainId());

  let bentoBoxV1Address;

  if (chainId === 31337) {
    const WETH9 = await ethers.getContractFactory("WETH9");
    const weth9 = await WETH9.deploy();
    const BentoBoxV1 = await ethers.getContractFactory("BentoBoxV1");
    const bentoBoxV1 = await BentoBoxV1.deploy(weth9.address);
    bentoBoxV1Address = bentoBoxV1.address;
  } else {
    if (!(chainId in WNATIVE)) {
      throw Error(`No WETH on chain #${chainId}!`);
    } else if (!(chainId in BENTOBOX_ADDRESS)) {
      throw Error(`No BENTOBOX on chain #${chainId}!`);
    }
    bentoBoxV1Address = BENTOBOX_ADDRESS[chainId as ChainId];
  }

  const { address } = await deploy("MasterDeployer", {
    from: deployer,
    args: [17, feeTo, bentoBoxV1Address],
    deterministicDeployment: false,
  });

  console.log("MasterDeployer deployed at ", address);
};

export default deployFunction;

deployFunction.tags = ["MasterDeployer"];

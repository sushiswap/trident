import { BENTOBOX_ADDRESS, ChainId, WNATIVE } from "@sushiswap/sdk";

import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  ethers,
  deployments,
  getNamedAccounts,
  getChainId,
}: HardhatRuntimeEnvironment) {
  console.log("Running SwapRouter deploy script");
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = Number(await getChainId()) as ChainId;

  let bentoBoxV1Address;
  let wethAddress;

  if (chainId === ChainId.HARDHAT) {
    const WETH9 = await ethers.getContractFactory("WETH9");
    const weth9 = await WETH9.deploy();
    const BentoBoxV1 = await ethers.getContractFactory("BentoBoxV1");
    const bentoBoxV1 = await BentoBoxV1.deploy(weth9.address);
    bentoBoxV1Address = bentoBoxV1.address;
    wethAddress = weth9.address;
  } else {
    if (!(chainId in WNATIVE)) {
      throw Error(`No WETH on chain #${chainId}!`);
    } else if (!(chainId in BENTOBOX_ADDRESS)) {
      throw Error(`No BENTOBOX on chain #${chainId}!`);
    }
    bentoBoxV1Address = BENTOBOX_ADDRESS[chainId];
    wethAddress = WNATIVE[chainId];
  }

  const { address: masterDeployerAdress } = await ethers.getContract(
    "MasterDeployer"
  );

  await deploy("SwapRouter", {
    from: deployer,
    args: [wethAddress, masterDeployerAdress, bentoBoxV1Address],
    deterministicDeployment: false,
  });
};

export default deployFunction;

deployFunction.dependencies = ["MasterDeployer"];

deployFunction.tags = ["SwapRouter"];

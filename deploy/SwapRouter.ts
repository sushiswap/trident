import { BENTOBOX_ADDRESS, ChainId, WNATIVE } from "@sushiswap/sdk"

import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

const deployFunction: DeployFunction =  async function ({ ethers, deployments, getNamedAccounts, getChainId }: HardhatRuntimeEnvironment) {
    console.log("Running SwapRouter deploy script")
    const { deploy } = deployments
  
    const { deployer } = await getNamedAccounts()
  
    const chainId = Number(await getChainId()) as ChainId;
    
    if (!(chainId in WNATIVE)) {
        throw Error(`No WETH on chain #${chainId}!`);
    } else if (!(chainId in BENTOBOX_ADDRESS)) {
        throw Error(`No BENTOBOX on chain #${chainId}!`);
    }

    const { address: weth9Address } = WNATIVE[chainId]
    
    const { address: masterDeployerAdress } = await ethers.getContract("MasterDeployer")

    await deploy("SwapRouter", {
      from: deployer,
      args: [weth9Address, masterDeployerAdress, BENTOBOX_ADDRESS[chainId]],
      deterministicDeployment: false
    })
}
  
export default deployFunction

deployFunction.dependencies = ['MasterDeployer'];

deployFunction.tags = ["SwapRouter"]
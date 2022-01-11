import { BENTOBOX_ADDRESS, ChainId, WNATIVE } from '@sushiswap/core-sdk'

import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

const deployFunction: DeployFunction = async function ({
  ethers,
  deployments,
  getNamedAccounts,
  getChainId,
}: HardhatRuntimeEnvironment) {
  // console.log("Running MasterDeployer deploy script");
  const { deploy } = deployments

  const barFee = 0

  const { deployer, barFeeTo } = await getNamedAccounts()

  const chainId = parseInt(await getChainId())

  let bentoBoxV1Address

  // TODO: Messy, can share deployment from @sushiswap/bentobox
  if (chainId === 31337) {
    // for testing purposes we use a redeployed bentobox address
    bentoBoxV1Address = (await ethers.getContract('BentoBoxV1')).address
  } else if (!(chainId in WNATIVE)) {
    throw Error(`No WETH on chain #${chainId}!`)
  } else if (!(chainId in BENTOBOX_ADDRESS)) {
    throw Error(`No BENTOBOX on chain #${chainId}!`)
  } else {
    bentoBoxV1Address = BENTOBOX_ADDRESS[chainId]
  }

  const { address } = await deploy('MasterDeployer', {
    from: deployer,
    args: [barFee, barFeeTo, bentoBoxV1Address],
    deterministicDeployment: false,
  })

  // console.log("MasterDeployer deployed at ", address);
}

export default deployFunction

deployFunction.dependencies = ['BentoBoxV1']

deployFunction.tags = ['MasterDeployer']

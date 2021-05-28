import { ethers } from "hardhat";
import { expect } from "chai";
import { prepare, deploy, getBigNumber } from "./utilities"

describe("MirinPoolBento", function () {
  before(async function () {
    await prepare(this, ["ERC20Mock", "BentoBoxV1Flat", "MirinPoolBento"])
  })

  beforeEach(async function () {
    // Deploy ERC20 Mocks, BentoBox & Pool
    await deploy(this, [
      ["weth", this.ERC20Mock, ["WETH", "ETH", getBigNumber("10000000")]],
      ["sushi", this.ERC20Mock, ["SUSHI", "SUSHI", getBigNumber("10000000")]],
      ["dai", this.ERC20Mock, ["DAI", "DAI", getBigNumber("10000000")]],
      ["bento", this.BentoBoxV1Flat, [this.weth.address]],
      ["pool", this.MirinPoolBento, [this.bento.address, this.sushi.address, this.dai.address, "0x0000000000000000000000000000000000000000000000000000000000000001", 1, this.alice.address]]
    ])
    // Whitelist Pool on BentoBox
    await this.bento.whitelistMasterContract(this.pool.address, true)
    // Approve BentoBox token deposits
    await this.sushi.approve(this.bento.address, getBigNumber(10000))
    await this.dai.approve(this.bento.address, getBigNumber(10000))
    // Make BentoBox token deposits to Pool
    await this.bento.deposit(this.sushi.address, this.alice.address, this.pool.address, getBigNumber(1000), 0)
    await this.bento.deposit(this.dai.address, this.alice.address, this.pool.address, getBigNumber(100), 0)
    // Approve Pool to spend 'alice' BentoBox tokens
    await this.bento.setMasterContractApproval(this.alice.address, this.pool.address, true, "0", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000")
  })
})

// @ts-nocheck

import { BigNumber } from "ethers";
import { Multicall } from "../../typechain/Multicall";
import { ethers } from "hardhat";
import { expect } from "chai";
import { getBigNumber } from "./helpers";

let accounts = [];
// First token is used as weth
let tokens = [];
let pools = [];
let bento, masterDeployer, router;

export async function initialize() {
  if (accounts.length > 0) {
    return;
  }
  accounts = await ethers.getSigners();

  const ERC20 = await ethers.getContractFactory("ERC20Mock");
  const Bento = await ethers.getContractFactory("BentoBoxV1");
  const Deployer = await ethers.getContractFactory("MasterDeployer");
  const PoolFactory = await ethers.getContractFactory(
    "ConstantProductPoolFactory"
  );
  const TridentRouter = await ethers.getContractFactory("TridentRouter");
  const Pool = await ethers.getContractFactory("ConstantProductPool");

  let promises = [];
  for (let i = 0; i < 4; i++) {
    promises.push(ERC20.deploy("Token" + i, "TOK" + i, getBigNumber(1000000)));
  }
  tokens = await Promise.all(promises);

  bento = await Bento.deploy(tokens[0].address);
  masterDeployer = await Deployer.deploy(
    17,
    accounts[0].address,
    bento.address
  );
  router = await TridentRouter.deploy(bento.address, tokens[0].address);
  const poolFactory = await PoolFactory.deploy(masterDeployer.address);

  await Promise.all([
    // Whitelist pool factory in master deployer
    masterDeployer.addToWhitelist(poolFactory.address),
    // Whitelist Router on BentoBox
    bento.whitelistMasterContract(router.address, true),
  ]);

  // Approve BentoBox token deposits and deposit tokens in bentobox
  promises = [];
  for (let i = 0; i < tokens.length; i++) {
    promises.push(
      tokens[i].approve(bento.address, getBigNumber(1000000)).then(() => {
        bento.deposit(
          tokens[i].address,
          accounts[0].address,
          accounts[0].address,
          getBigNumber(500000),
          0
        );
      })
    );
  }
  await Promise.all(promises);

  // Approve Router to spend alice's BentoBox tokens
  await bento.setMasterContractApproval(
    accounts[0].address,
    router.address,
    true,
    "0",
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  );

  // Create pools
  promises = [];
  for (let i = 0; i < tokens.length; i++) {
    for (let j = i + 1; j < tokens.length; j++) {
      // Pool deploy data
      let addresses = [tokens[i].address, tokens[j].address].sort();
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint8", "bool"],
        [addresses[0], addresses[1], 30, false]
      );
      promises.push(
        masterDeployer
          .deployPool(poolFactory.address, deployData)
          .then((tx) => {
            return tx.wait();
          })
          .then((tx) => {
            return Pool.attach(tx.events[0].args[1]);
          })
      );
    }
  }
  pools = await Promise.all(promises);
}

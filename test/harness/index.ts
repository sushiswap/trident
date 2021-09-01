// @ts-nocheck

import { BigNumber, utils } from "ethers";
import { Multicall } from "../../typechain/Multicall";
import { ethers } from "hardhat";
import { expect } from "chai";
import { getBigNumber } from "./helpers";
import { Token } from "@sushiswap/sdk";

let accounts = [];
// First token is used as weth
let tokens = [];
let pools = [];
let bento, masterDeployer, router;
let poolTokens = new Map();

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
      let token0, token1;
      if (tokens[i].address < tokens[j].address) {
        token0 = tokens[i];
        token1 = tokens[j];
      } else {
        token0 = tokens[j];
        token1 = tokens[i];
      }
      const deployData = utils.defaultAbiCoder.encode(
        ["address", "address", "uint8", "bool"],
        [token0.address, token1.address, 30, false]
      );
      const salt = utils.keccak256(deployData);
      const constructorParams = utils.defaultAbiCoder
        .encode(["bytes", "address"], [deployData, masterDeployer.address])
        .substring(2);
      const initCodeHash = utils.keccak256(Pool.bytecode + constructorParams);
      const poolAddress = utils.getCreate2Address(
        poolFactory.address,
        salt,
        initCodeHash
      );
      poolTokens.set(poolAddress, [token0, token1]);
      pools.push(poolAddress);

      promises.push(masterDeployer.deployPool(poolFactory.address, deployData));
    }
  }
  await Promise.all(promises);
}

export async function addLiquidity(poolNumber, amount0, amount1) {
  let pool = pools[poolNumber];
  let [token0, token1] = poolTokens.get(pool.address);
  let [iTS, iPB0, iPB1, iUB0, iUB1, iUNB0, iUNB1] = await getBalances(
    pool.address,
    accounts[0].address,
    token0,
    token1
  );

  let liquidityInput = [
    {
      token: token0.address,
      native: false,
      amount: BigNumber.from(10).pow(18),
    },
    {
      token: sushi.address,
      native: false,
      amount: BigNumber.from(10).pow(18),
    },
  ];
  await router.addLiquidity(liquidityInput, pool.address, 1, aliceEncoded);
  let intermediateTotalSupply = await pool.totalSupply();
  let intermediatePoolWethBalance = await bento.balanceOf(
    weth.address,
    pool.address
  );
  let intermediatePoolSushiBalance = await bento.balanceOf(
    sushi.address,
    pool.address
  );

  expect(intermediateTotalSupply).gt(initialTotalSupply);
  expect(intermediatePoolWethBalance).eq(
    initialPoolWethBalance.add(BigNumber.from(10).pow(18))
  );
  expect(intermediatePoolSushiBalance).eq(
    initialPoolSushiBalance.add(BigNumber.from(10).pow(18))
  );
  expect(
    intermediatePoolWethBalance
      .mul(BigNumber.from(10).pow(36))
      .div(intermediateTotalSupply)
  ).eq(
    initialPoolWethBalance
      .mul(BigNumber.from(10).pow(36))
      .div(initialTotalSupply)
  );
  expect(
    intermediatePoolSushiBalance
      .mul(BigNumber.from(10).pow(36))
      .div(intermediateTotalSupply)
  ).eq(
    initialPoolSushiBalance
      .mul(BigNumber.from(10).pow(36))
      .div(initialTotalSupply)
  );
}

async function getBalances(pool, user, token0, token1) {
  return Promise.all([
    pool.totalSupply(),
    bento.balanceOf(token0.address, pool),
    bento.balanceOf(token1.address, pool),
    bento.balanceOf(token0.address, user),
    bento.balanceOf(token1.address, user),
    token0.balanceOf(user),
    token1.balanceOf(user),
  ]);
}

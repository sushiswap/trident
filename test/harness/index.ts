// @ts-nocheck

import { BigNumber, utils } from "ethers";
import { Multicall } from "../../typechain/Multicall";
import { ethers } from "hardhat";
import { expect } from "chai";
import { getBigNumber, sqrt, ZERO, TWO } from "./helpers";
import { Token } from "@sushiswap/sdk";

const MAX_FEE = BigNumber.from(10000);

let accounts = [];
// First token is used as weth
let tokens = [];
let pools = [];
let bento, masterDeployer, router;
let poolTokens = new Map();
let aliceEncoded;

export async function initialize() {
  if (accounts.length > 0) {
    return;
  }
  accounts = await ethers.getSigners();
  aliceEncoded = utils.defaultAbiCoder.encode(
    ["address"],
    [accounts[0].address]
  );

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
      pools.push(Pool.attach(poolAddress));

      promises.push(masterDeployer.deployPool(poolFactory.address, deployData));
    }
  }
  await Promise.all(promises);

  // Add initial liquidity of 1k tokens each to every pool
  promises = [];
  for (let i = 0; i < pools.length; i++) {
    promises.push(addLiquidity(i, getBigNumber(1000), getBigNumber(1000)));
  }
  await Promise.all(promises);
}

export async function addLiquidity(
  poolNumber,
  amount0,
  amount1,
  native0 = false,
  native1 = false
) {
  let pool = pools[poolNumber];
  let [token0, token1] = poolTokens.get(pool.address);

  // [iTS, iPB0, iPB1, iUB0, iUB1, iUNB0, iUNB1]
  const initialBalances = await getBalances(
    pool,
    accounts[0].address,
    token0,
    token1
  );

  let liquidityInput = [
    {
      token: token0.address,
      native: native0,
      amount: amount0,
    },
    {
      token: token1.address,
      native: native1,
      amount: amount1,
    },
  ];

  const [kLast, barFee, swapFee] = await Promise.all([
    pools[poolNumber].kLast(),
    masterDeployer.barFee(),
    pools[poolNumber].swapFee(),
  ]);
  const preMintComputed = sqrt(initialBalances[1].mul(initialBalances[2]));
  const feeMint = preMintComputed.isZero()
    ? ZERO
    : initialBalances[0]
        .mul(preMintComputed.sub(kLast).mul(barFee))
        .div(preMintComputed.mul(MAX_FEE));
  const updatedTotalSupply = feeMint.add(initialBalances[0]);
  const [fee0, fee1] = unoptimalMintFee(
    amount0,
    amount1,
    initialBalances[1],
    initialBalances[2],
    swapFee
  );
  const computed = sqrt(
    initialBalances[1]
      .add(amount0.sub(fee0))
      .mul(initialBalances[2].add(amount1.sub(fee1)))
  );
  const computedLiquidity = preMintComputed.isZero()
    ? computed.sub(BigNumber.from(1000))
    : computed
        .sub(preMintComputed)
        .mul(initialBalances[0])
        .div(preMintComputed);

  await router.addLiquidity(
    liquidityInput,
    pool.address,
    computedLiquidity,
    aliceEncoded
  );

  const finalBalances = await getBalances(
    pool,
    accounts[0].address,
    token0,
    token1
  );
}

async function getBalances(pool, user, token0, token1) {
  return Promise.all([
    pool.totalSupply(),
    bento.balanceOf(token0.address, pool.address),
    bento.balanceOf(token1.address, pool.address),
    bento.balanceOf(token0.address, user),
    bento.balanceOf(token1.address, user),
    token0.balanceOf(user),
    token1.balanceOf(user),
  ]);
}

function unoptimalMintFee(amount0, amount1, reserve0, reserve1, swapFee) {
  if (reserve0.isZero() || reserve1.isZero()) return [ZERO, ZERO];

  const amount1Optimal = amount0.mul(reserve1).div(reserve0);
  if (amount1Optimal.lte(amount1)) {
    return [
      ZERO,
      swapFee.mul(amount1.sub(amount1Optimal)).div(MAX_FEE.mul(TWO)),
    ];
  } else {
    const amount1Optimal = amount1.mul(reserve0).div(reserve1);
    return [
      swapFee.mul(amount0.sub(amount0Optimal)).div(MAX_FEE.mul(TWO)),
      ZERO,
    ];
  }
}

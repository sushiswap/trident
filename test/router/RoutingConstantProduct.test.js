const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const seedrandom = require("seedrandom")
const { calcOutByIn, calcInByOut } = require("@sushiswap/sdk");
const { prepare, deploy, getBigNumber } = require("../utilities");

const testSeed = '2';   // Change it to change random generator values
const rnd = seedrandom(testSeed); // random [0, 1)

const MINIMUM_LIQUIDITY = 1000;

function getIntegerRandomValue(exp) {
  if (exp <= 15) {
    const value = Math.floor(rnd()*Math.pow(10, exp));
    return [value, BigNumber.from(value)];
  } else {
    const random = Math.floor(rnd()*1e15);
    const value = random*Math.pow(10, exp-15);
    const bnValue = BigNumber.from(10).pow(exp-15).mul(random);
    return [value, bnValue];
  }
}

function getIntegerRandomValueWithMin(exp, min = 0) {
  let res;
  do {
    res = getIntegerRandomValue(exp);
  } while (res[0] < min)
  return res;
}

function areCloseValues(v1, v2, threshould) {
  if (threshould == 0)
    return v1 == v2;
  if  (v1 < 1/threshould)
    return Math.abs(v1-v2) <= 1.1;
  return Math.abs(v1/v2 - 1) < threshould;
}

describe("ConstantProductPool Typescript == Solidity check", function () {
  let alice, feeTo, usdt, usdc, weth, bento, masterDeployer, tridentPoolFactory, router, Pool;

  async function createConstantProductPool(fee, res0exp, res1exp) {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("ConstantProductPoolFactory");
    const SwapRouter = await ethers.getContractFactory("TridentRouter");
    Pool = await ethers.getContractFactory("ConstantProductPool");
    
    weth = await ERC20.deploy("WETH", "WETH", getBigNumber("1000000000000000000"));
    await weth.deployed();
    usdt = await ERC20.deploy("USDT", "USDT", getBigNumber("1000000000000000000"));
    await usdt.deployed();
    usdc = await ERC20.deploy("USDC", "USDC", getBigNumber("1000000000000000000"));
    await usdc.deployed();

    bento = await Bento.deploy(weth.address);
    await bento.deployed();

    masterDeployer = await Deployer.deploy(17, feeTo.address, bento.address);
    await masterDeployer.deployed();

    tridentPoolFactory = await PoolFactory.deploy(masterDeployer.address);
    await tridentPoolFactory.deployed();
    router = await SwapRouter.deploy(bento.address, weth.address);
    await router.deployed();

    // Whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(tridentPoolFactory.address);

    // Whitelist Router on BentoBox
    await bento.whitelistMasterContract(router.address, true);
    // Approve BentoBox token deposits
    await usdc.approve(bento.address, getBigNumber("1000000000000000000"));
    await usdt.approve(bento.address, getBigNumber("1000000000000000000"));
    // Make BentoBox token deposits
    await bento.deposit(usdc.address, alice.address, alice.address, getBigNumber("1000000000000000000"), 0);
    await bento.deposit(usdt.address, alice.address, alice.address, getBigNumber("1000000000000000000"), 0);
    // Approve Router to spend 'alice' BentoBox tokens
    await bento.setMasterContractApproval(alice.address, router.address, true, "0", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000");

    const [address0, address1] = usdt.address.toUpperCase() < usdc.address.toUpperCase() ? [usdt.address, usdc.address] : [usdc.address, usdt.address]
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256", "bool"],
      [address0, address1, Math.round(fee*10_000), true]
    );
    const pool = await Pool.attach(
      (await (await masterDeployer.deployPool(tridentPoolFactory.address, deployData)).wait()).events[0].args[1]
    );

    const [jsVal0, bnVal0] = getIntegerRandomValueWithMin(res0exp, MINIMUM_LIQUIDITY);
    const [jsVal1, bnVal1] = res1exp == undefined ? [jsVal0, bnVal0] : getIntegerRandomValueWithMin(res1exp, MINIMUM_LIQUIDITY);
    await bento.transfer(usdt.address, alice.address, pool.address, bnVal0);
    await bento.transfer(usdc.address, alice.address, pool.address, bnVal1);
    await pool.mint(alice.address);
  
    const poolInfo = {
      type: 'ConstantProduct',
      reserve0: jsVal0,
      reserve1: jsVal1,
      fee
    }

    return [poolInfo, pool];
  }

  let swapDirection = true;
  async function checkSwap(pool, poolRouterInfo, swapAmountExp) {
    const [jsValue, bnValue] = getIntegerRandomValue(swapAmountExp);
    const [t0, t1] = swapDirection ? [usdt.address, usdc.address] : [usdc.address, usdt.address]
    const amountOutPool = (await pool.getAmountOut(t0, t1, bnValue)).toString();
    const amountOutPrediction = calcOutByIn(poolRouterInfo, jsValue, swapDirection);
    //console.log(Math.abs(amountOutPrediction/amountOutPool-1), amountOutPrediction, amountOutPool);
    expect(areCloseValues(amountOutPrediction, amountOutPool, 1e-12)).equals(true);
    const reserveOut = swapDirection ? poolRouterInfo.reserve1 : poolRouterInfo.reserve0;
    if (reserveOut - amountOutPool < MINIMUM_LIQUIDITY)
      return;
    const amounInExpected = calcInByOut(poolRouterInfo, amountOutPrediction, swapDirection);
    const amountOutPrediction2 = calcOutByIn(poolRouterInfo, amounInExpected, swapDirection);
    // console.log(Math.abs(amounInExpected/jsValue-1), amounInExpected, jsValue);
    // console.log(Math.abs(amountOutPrediction/amountOutPrediction2-1), amountOutPrediction, amountOutPrediction2);
    expect(
      areCloseValues(amounInExpected, jsValue, 1e-12) 
      || areCloseValues(amountOutPrediction, amountOutPrediction2, 1e-12)
    ).equals(true);
    swapDirection = !swapDirection;
  }

  describe("Check regular liquidity values", function () {
    for (let mintNum = 0; mintNum < 10; ++mintNum) {
      it(`Test ${mintNum+1}`, async function() {
        const [poolRouterInfo, pool] = await createConstantProductPool(0.003, 19, 19);

        // test regular values
        for (let swapNum = 0; swapNum < 30; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 17);
        }
        // test small values
        for (let swapNum = 0; swapNum < 5; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 2);
        }
        //test extremely big values 2^112 = 10^33.7153
        for (let swapNum = 0; swapNum < 10; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 33);
        }
      });
    }
  })

  describe("Check supersmall liquidity values", function () {
    for (let mintNum = 0; mintNum < 10; ++mintNum) {
      it(`Test ${mintNum+1}`, async function() {
        const [poolRouterInfo, pool] = await createConstantProductPool(0.003, 4, 4);

        // test regular values
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 17);
        }
        // test small values
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 2);
        }
        //test extremely big values 2^112 = 10^33.7153
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 33);
        }
      })
    }
  })

  describe("Check superbig liquidity values", function () {
    for (let mintNum = 0; mintNum < 10; ++mintNum) {
      it(`Test ${mintNum+1}`, async function() {
        const [poolRouterInfo, pool] = await createConstantProductPool(0.003, 33, 33);

        // test regular values
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 17);
        }
        // test small values
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 2);
        }
        //test extremely big values 2^112 = 10^33.7153
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 33);
        }
      });
    }
  })

  describe("Check different fees", function () {
    for (let mintNum = 0; mintNum < 10; ++mintNum) {
      const fee = (mintNum+1)/1000;
      it(`fee = ${fee}`, async function() {
        const [poolRouterInfo, pool] = await createConstantProductPool(fee, 19, 19);

        // test regular values
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 17);
        }
        // test small values
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 2);
        }
        //test extremely big values 2^112 = 10^33.7153
        for (let swapNum = 0; swapNum < 3; ++swapNum) {
          await checkSwap(pool, poolRouterInfo, 33);
        }
      });
    }
  })
})

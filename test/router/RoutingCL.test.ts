// @ts-nocheck
import { ethers } from "hardhat";
import { getBigNumber } from "../utilities";
import { expect } from "chai";
import { ERC20Mock } from "../../typechain/ERC20Mock";
import { BentoBoxV1 } from "../../typechain/BentoBoxV1";
import { ConcentratedLiquidityPool } from "../../typechain/ConcentratedLiquidityPool";
import { ConcentratedLiquidityPoolFactory } from "../../typechain/ConcentratedLiquidityPoolFactory";
import { getSqrtX96Price } from "../utilities/sqrtPrice";
import { BigNumber } from "ethers";
import {
  ConcentratedLiquidityPool as ConLiqPoolInfo,
  CL_MIN_TICK,
  CL_MAX_TICK,
  calcOutByIn,
  getBigNumber,
} from "@sushiswap/sdk";

describe.only("Concentrated liquidity pool", function () {
  let alice: ethers.Signer,
    feeTo: ethers.Signer,
    weth: ERC20Mock,
    dai: ERC20Mock,
    usd: ERC20Mock,
    tridentPoolFactory: ConcentratedLiquidityPoolFactory,
    pool0: ConcentratedLiquidityPool,
    pool1: ConcentratedLiquidityPool,
    tickMath: TickMathTest,
    bento: BentoBoxV1;

  const totalSupply = getBigNumber("100000000");
  const priceMultiplier = BigNumber.from("0x1000000000000000000000000");

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Pool = await ethers.getContractFactory("ConcentratedLiquidityPool");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const MasterDeployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory(
      "ConcentratedLiquidityPoolFactory"
    );
    const TickMathTest = await ethers.getContractFactory("TickMathTest");
    weth = await ERC20.deploy("", "", totalSupply);
    dai = await ERC20.deploy("", "", totalSupply);
    usd = await ERC20.deploy("", "", totalSupply);
    // lets require dai < weth to match what is on chain
    if (dai.address.toUpperCase() > weth.address.toUpperCase()) {
      let tmp = { ...weth };
      weth = { ...dai };
      dai = tmp;
    }
    // and weth < usd so the prices make sense
    if (weth.address.toUpperCase() > usd.address.toUpperCase()) {
      let tmp = { ...weth };
      weth = { ...usd };
      usd = tmp;
    }
    tickMath = await TickMathTest.deploy();
    bento = await Bento.deploy(weth.address);
    await weth.approve(bento.address, totalSupply);
    await dai.approve(bento.address, totalSupply);
    await usd.approve(bento.address, totalSupply);
    const masterDeployer = await MasterDeployer.deploy(
      10,
      feeTo.address,
      bento.address
    );

    tridentPoolFactory = await PoolFactory.deploy(masterDeployer.address);
    await tridentPoolFactory.deployed();

    await bento.deposit(
      weth.address,
      alice.address,
      alice.address,
      totalSupply,
      0
    );

    await bento.deposit(
      usd.address,
      alice.address,
      alice.address,
      totalSupply,
      0
    );

    await bento.deposit(
      dai.address,
      alice.address,
      alice.address,
      totalSupply,
      0
    );

    // whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(tridentPoolFactory.address);

    // divided by 2**96 equals 0.02280974803
    // squared and inverted this is 1922.02 (price of eth in dai)
    // corresponds to tick -75616
    let sqrtPrice = BigNumber.from("1807174424252647735792984898");

    let deployData0 = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint24", "uint160"],
      [dai.address, weth.address, 1000, sqrtPrice]
    );

    // deploy pool0
    pool0 = await Pool.attach(
      (
        await (
          await masterDeployer.deployPool(
            tridentPoolFactory.address,
            deployData0
          )
        ).wait()
      ).events[0].args[1]
    );

    // current eth price is $2500
    sqrtPrice = BigNumber.from("50").mul("0x1000000000000000000000000");

    let deployData1 = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint24", "uint160"],
      [weth.address, usd.address, 1000, sqrtPrice]
    );

    // deploy pool1
    pool1 = await Pool.attach(
      (
        await (
          await masterDeployer.deployPool(
            tridentPoolFactory.address,
            deployData1
          )
        ).wait()
      ).events[0].args[1]
    );

    // Current price is 2500, we are gonna mint liquidity on intervals ~ [1600, 3600] and ~ [2600, 3000]
    const lowerTick1 = 73780; // price 1599
    const lowerTick1Price = await tickMath.getSqrtRatioAtTick(lowerTick1);
    const upperTick1 = 81891; // price 3600
    const upperTick1Price = await tickMath.getSqrtRatioAtTick(upperTick1);
    const currentTick = 78244; // price 2500
    const currentTickPrice = await pool1.price();
    const lowerTick2 = 78640; // price 2601
    const lowerTick2Price = await tickMath.getSqrtRatioAtTick(lowerTick2);
    const upperTick2 = 80149; // price ~3025
    const upperTick2Price = await tickMath.getSqrtRatioAtTick(upperTick2);

    // mint liquidity with 4k usd and x amount of eth
    // liquidity amount can be arbitrary for this test
    const liquidity = getBigNumber("4000")
      .mul(priceMultiplier)
      .div(currentTickPrice.sub(lowerTick1Price));

    await bento.transfer(
      weth.address,
      alice.address,
      pool1.address,
      getDx(liquidity, currentTickPrice, upperTick1Price)
    );

    await bento.transfer(
      usd.address,
      alice.address,
      pool1.address,
      getDy(liquidity, lowerTick1Price, currentTickPrice)
    );

    let mintData = ethers.utils.defaultAbiCoder.encode(
      ["int24", "int24", "int24", "int24", "uint128", "address"],
      [-887272, lowerTick1, lowerTick1, upperTick1, liquidity, alice.address]
    );

    await pool1.mint(mintData);

    await bento.transfer(
      weth.address,
      alice.address,
      pool1.address,
      getDx(liquidity, lowerTick2Price, upperTick2Price)
    );

    mintData = ethers.utils.defaultAbiCoder.encode(
      ["int24", "int24", "int24", "int24", "uint128", "address"],
      [lowerTick1, lowerTick2, lowerTick2, upperTick2, liquidity, alice.address]
    );

    await pool1.mint(mintData);
  });

  it("check swap", async () => {
    await checkSwap(pool1, 1000, true, alice);

    const min = -887272;
    const max = -min - 1;

    const minTick = await pool0.ticks(min);
    const maxTick = await pool0.ticks(max);

    expect(minTick.previousTick).to.be.eq(min);
    expect(minTick.nextTick).to.be.eq(max);
    expect(maxTick.previousTick).to.be.eq(min);
    expect(maxTick.nextTick).to.be.eq(max);
  });
});

function getDx(liquidity, priceLower, priceUpper, roundUp = true) {
  const increment = roundUp ? 1 : 0;
  return liquidity
    .mul("0x1000000000000000000000000")
    .mul(priceUpper.sub(priceLower))
    .div(priceUpper)
    .div(priceLower)
    .add(increment);
}

function getDy(liquidity, priceLower, priceUpper, roundUp = true) {
  const increment = roundUp ? 1 : 0;
  return liquidity
    .mul(priceUpper.sub(priceLower))
    .div("0x1000000000000000000000000")
    .add(increment);
}

const clPriceBase = Math.pow(2, 96);
async function getCLPoolInfo(pool: ConcentratedLiquidityPool): ConLiqPoolInfo {
  const token0 = await pool.token0();
  const token1 = await pool.token1();

  const nearestTickIndex = await pool.nearestTick();
  let nearestTick;
  const ticks = [];
  let index = CL_MIN_TICK;
  let prevTick;
  do {
    prevTick = index;
    const tick = await pool.ticks(index);
    ticks.push({
      index,
      DLiquidity: parseInt(tick.liquidity.toString()),
    });

    if (index == nearestTickIndex) nearestTick = ticks.length - 1;
    index = tick.nextTick;
  } while (prevTick != index);
  console.assert(index == CL_MAX_TICK, "Error 258");
  console.assert(nearestTick !== undefined, "Error 259");

  return new ConLiqPoolInfo({
    address: pool.address,
    token0: {
      name: token0,
      address: token0,
    },
    token1: {
      name: token1,
      address: token1,
    },
    fee: (await pool.swapFee()) / 1_000_000,
    liquidity: parseInt((await pool.liquidity()).toString()),
    sqrtPrice: parseInt((await pool.price()).toString()) / clPriceBase,
    nearestTick,
    ticks,
  });
}

async function predictOutput(
  pool: ConcentratedLiquidityPool,
  amountIn: number,
  direction: boolean
) {
  const poolInfo = await getCLPoolInfo(pool);
  const out = calcOutByIn(poolInfo, amountIn, direction);
  return out;
}

async function checkSwap(
  pool: ConcentratedLiquidityPool,
  amountIn: number,
  direction: boolean,
  recipient: ethers.Signer
) {
  const poolInfo = await getCLPoolInfo(pool);
  const outPredicted = calcOutByIn(poolInfo, amountIn, direction);

  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["bool", "uint256", "address", "bool"],
    [direction, getBigNumber(amountIn), recipient.address, false]
  );
  const out = await pool.swap(swapData);

  console.log(out.toString(), outPredicted);
}

// @ts-nocheck
import { ethers } from "hardhat";
import { getBigNumber } from "./utilities";
import { expect } from "chai";
import { ERC20Mock } from "../typechain/ERC20Mock";
import { BentoBoxV1 } from "../typechain/BentoBoxV1";
import { ConcentratedLiquidityPool } from "../typechain/ConcentratedLiquidityPool";
import { getSqrtX96Price } from "./utilities/sqrtPrice";
import { BigNumber } from "ethers";

describe.only("Concentrated liqudity pool", function () {
  let alice: ethers.Signer,
    feeTo: ethers.Signer,
    weth: ERC20Mock,
    dai: ERC20Mock,
    usd: ERC20Mock,
    pool1: ConcentratedLiquidityPool,
    pool2: ConcentratedLiquidityPool,
    tickMath: TickMathTest,
    bento: BentoBoxV1;

  const totalSupply = getBigNumber("100000000");
  const priceMultiplier = BigNumber.from("0x1000000000000000000000000");

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Clp = await ethers.getContractFactory("ConcentratedLiquidityPool");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const MasterDeployer = await ethers.getContractFactory("MasterDeployer");
    const TickMathTest = await ethers.getContractFactory("TickMathTest");
    weth = await ERC20.deploy("WETH", "ETH", totalSupply);
    dai = await ERC20.deploy("DAI", "DAI", totalSupply);
    usd = await ERC20.deploy("USD", "USD", totalSupply);
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
    // todo write factory & deploy through master deplyoer

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

    let sqrtPrice = BigNumber.from("1807174424252647735792984898");
    // divided by 2**96 equals 0.02280974803
    // squared and inverted this is 1922.02 (price of eth in dai)
    // corresponds to tick -75616

    let deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint24", "uint160"],
      [dai.address, weth.address, 1000, sqrtPrice] // dai is token0 (x)
    );
    pool1 = await Clp.deploy(deployData, masterDeployer.address);

    sqrtPrice = BigNumber.from("50").mul("0x1000000000000000000000000");
    // current eth price is $2500

    deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint24", "uint160"],
      [weth.address, usd.address, 1000, sqrtPrice] // weth is token0 (x) ... usd is token 1 ... price is y/x
    );
    pool2 = await Clp.deploy(deployData, masterDeployer.address);

    // Current price is 2500, we are gonna mint liquidity on intervals ~ [1600, 3600] and ~ [2600, 3000]
    const lowerTick1 = 73780; // price 1599
    const lowerTick1Price = await tickMath.getSqrtRatioAtTick(lowerTick1);
    const upperTick1 = 81891; // price 3600
    const upperTick1Price = await tickMath.getSqrtRatioAtTick(upperTick1);
    const currentTick = 78244; // price 2500
    const currentTickPrice = await pool2.price();
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
      pool2.address,
      getDx(liquidity, currentTickPrice, upperTick1Price)
    );

    await bento.transfer(
      usd.address,
      alice.address,
      pool2.address,
      getDy(liquidity, lowerTick1Price, currentTickPrice)
    );

    let mintData = ethers.utils.defaultAbiCoder.encode(
      ["int24", "int24", "int24", "int24", "uint128", "address"],
      [-887272, lowerTick1, lowerTick1, upperTick1, liquidity, alice.address]
    );

    await pool2.mint(mintData);

    await bento.transfer(
      weth.address,
      alice.address,
      pool2.address,
      getDx(liquidity, lowerTick2Price, upperTick2Price)
    );

    mintData = ethers.utils.defaultAbiCoder.encode(
      ["int24", "int24", "int24", "int24", "uint128", "address"],
      [lowerTick1, lowerTick2, lowerTick2, upperTick2, liquidity, alice.address]
    );

    await pool2.mint(mintData);
  });

  it("pool1 - should initialize correctly", async () => {
    const min = -887272;
    const max = 887271;

    const minTick = await pool1.ticks(min);
    const maxTick = await pool1.ticks(max);

    expect(minTick.previousTick).to.be.eq(min);
    expect(minTick.nextTick).to.be.eq(max);
    expect(maxTick.previousTick).to.be.eq(min);
    expect(maxTick.nextTick).to.be.eq(max);

    expect(await pool1.liquidity()).to.be.eq(0);
  });

  it("pool1 - should add liquidity inside price range", async () => {
    // current price is 1920 dai per eth ... mint liquidity from ~1000 to ~3000
    const lower = -80068; // 0.000333 dai per eth
    const upper = -69081; // 0.001 dai per eth
    const priceLower = await tickMath.getSqrtRatioAtTick(lower);
    const priceUpper = await tickMath.getSqrtRatioAtTick(upper);
    const currentPrice = await pool1.price();
    const startingLiquidity = await pool1.liquidity();

    const dP = currentPrice.sub(priceLower);

    const dy = getBigNumber(1);
    // calculate the amount of liq we mint based on dy and ticks
    const liquidity = dy.mul("0x1000000000000000000000000").div(dP);

    const dx = getDx(liquidity, currentPrice, priceUpper);

    await bento.transfer(dai.address, alice.address, pool1.address, dx);

    await bento.transfer(weth.address, alice.address, pool1.address, dy);

    let mintData = ethers.utils.defaultAbiCoder.encode(
      ["int24", "int24", "int24", "int24", "uint128", "address"],
      [-887272, lower, lower, upper, liquidity, alice.address]
    );

    await pool1.mint(mintData);

    expect((await pool1.liquidity()).toString()).to.be.eq(
      liquidity.add(startingLiquidity).toString(),
      "Didn't add right amount of liquidity"
    );
    expect(
      (await bento.balanceOf(dai.address, pool1.address)).toString()
    ).to.be.eq(
      "2683758334569795392629",
      "Didn't calculate token0 (dx) amount correctly"
    );
    expect(
      (await bento.balanceOf(weth.address, pool1.address)).toString()
    ).to.be.eq(dy.toString(), "Didn't calculate token1 (dy) amount correctly");
  });

  it("pool1 - shouldn't allow adding lower odd ticks and upper even ticks");

  it("pool1 - shouldn't allow adding ticks outside of min max bounds");

  // todo check that the existing ticks & liquidity make sense
  it("pool2 - Minted liquidity ticks in the right order");

  // todo check that the state doesn't change if we do swaps with 0 amountIn
  it("pool2 - should swap with 0 input and make no state changes");

  it("pool2 - Should execute trade within current tick - one for zero", async () => {
    const oldLiq = await pool2.liquidity();
    const oldTick = await pool2.nearestTick();
    const oldEthBalance = await bento.balanceOf(weth.address, alice.address);
    const oldUSDBalance = await bento.balanceOf(usd.address, alice.address);

    expect(oldLiq.gt(0)).to.be.true;

    const oldPrice = await pool2.price();

    // buy eth with 50 usd (one for zero, one is USD)
    await bento.transfer(
      usd.address,
      alice.address,
      pool2.address,
      getBigNumber(50)
    );
    let swapData = ethers.utils.defaultAbiCoder.encode(
      ["bool", "uint256", "address", "bool"],
      [false, getBigNumber(50), alice.address, false]
    );

    await pool2.swap(swapData);

    const newPrice = await pool2.price();
    const newTick = await pool2.nearestTick();
    const ethReceived = (
      await bento.balanceOf(weth.address, alice.address)
    ).sub(oldEthBalance);
    const usdPaid = oldUSDBalance.sub(
      await bento.balanceOf(usd.address, alice.address)
    );
    const tradePrice = parseInt(usdPaid.mul(100000).div(ethReceived)) / 100000;
    const tradePriceSqrtX96 = getSqrtX96Price(tradePrice);

    expect(usdPaid.toString()).to.be.eq(
      getBigNumber(50).toString(),
      "Didn't take the right usd amount"
    );
    expect(ethReceived.gt(0)).to.be.eq(true, "We didn't receive an eth");
    expect(oldPrice.lt(tradePriceSqrtX96)).to.be.eq(
      true,
      "Trade price isn't higher than starting price"
    );
    expect(newPrice.gt(tradePriceSqrtX96)).to.be.eq(
      true,
      "Trade price isn't lower than new price"
    );
    expect(oldPrice.lt(newPrice)).to.be.eq(true, "Price didn't increase");
    expect(oldTick).to.be.eq(newTick, "We crossed by mistake");
  });

  it("pool2 - should execute trade within current tick - zero for one", async () => {
    const oldLiq = await pool2.liquidity();
    const oldTick = await pool2.nearestTick();
    const oldEthBalance = await bento.balanceOf(weth.address, alice.address);
    const oldUSDBalance = await bento.balanceOf(usd.address, alice.address);

    expect(oldLiq.gt(0)).to.be.true;

    const oldPrice = await pool2.price();

    // buy usd with 0.1 eth
    await bento.transfer(
      weth.address,
      alice.address,
      pool2.address,
      getBigNumber(1, 17)
    );
    let swapData = ethers.utils.defaultAbiCoder.encode(
      ["bool", "uint256", "address", "bool"],
      [true, getBigNumber(1, 17), alice.address, false]
    );
    await pool2.swap(swapData);

    const newPrice = await pool2.price();
    const newTick = await pool2.nearestTick();
    const usdReceived = (await bento.balanceOf(usd.address, alice.address)).sub(
      oldUSDBalance
    );
    const ethPaid = oldEthBalance.sub(
      await bento.balanceOf(weth.address, alice.address)
    );
    const tradePrice = parseInt(usdReceived.mul(100000).div(ethPaid)) / 100000;
    const tradePriceSqrtX96 = getSqrtX96Price(tradePrice);

    expect(ethPaid.eq(getBigNumber(1).div(10))).to.be.true;
    expect(usdReceived.gt(0)).to.be.true;
    expect(oldPrice.gt(tradePriceSqrtX96)).to.be.true;
    expect(newPrice.lt(tradePriceSqrtX96)).to.be.true;
    expect(oldTick).to.be.eq(newTick, "We crossed by mistake");
    expect(oldPrice.gt(newPrice)).to.be.true;
  });

  it("pool2 - should execute trade and cross one tick - one for zero", async () => {
    const oldLiq = await pool2.liquidity();
    const oldTick = await pool2.nearestTick();
    const nextTick = (await pool2.ticks(oldTick)).nextTick;
    const oldEthBalance = await bento.balanceOf(weth.address, alice.address);
    const oldUSDBalance = await bento.balanceOf(usd.address, alice.address);

    expect(oldLiq.gt(0)).to.be.true;

    const oldPrice = await pool2.price();

    // buy eth with 1000 usd (one for zero, one is USD)
    await bento.transfer(
      usd.address,
      alice.address,
      pool2.address,
      getBigNumber(1000)
    );
    let swapData = ethers.utils.defaultAbiCoder.encode(
      ["bool", "uint256", "address", "bool"],
      [false, getBigNumber(1000), alice.address, false]
    );
    await pool2.swap(swapData);

    const newLiq = await pool2.liquidity();
    const newPrice = await pool2.price();
    const newTick = await pool2.nearestTick();
    const ethReceived = (
      await bento.balanceOf(weth.address, alice.address)
    ).sub(oldEthBalance);
    const usdPaid = oldUSDBalance.sub(
      await bento.balanceOf(usd.address, alice.address)
    );
    const tradePrice = parseInt(usdPaid.mul(100000).div(ethReceived)) / 100000;
    const tradePriceSqrtX96 = getSqrtX96Price(tradePrice);

    expect(usdPaid.toString()).to.be.eq(
      getBigNumber(1000).toString(),
      "Didn't take the right usd amount"
    );
    expect(ethReceived.gt(0)).to.be.eq(true, "Didn't receive any eth");
    expect(oldLiq.lt(newLiq)).to.be.eq(
      true,
      "We didn't cross into a more liquid range"
    );
    expect(oldPrice.lt(tradePriceSqrtX96)).to.be.eq(
      true,
      "Trade price isn't higher than starting price"
    );
    expect(newPrice.gt(tradePriceSqrtX96)).to.be.eq(
      true,
      "Trade price isn't lower than new price"
    );
    expect(oldPrice.lt(newPrice)).to.be.eq(true, "Price didn't increase");
    expect(newTick).to.be.eq(nextTick, "We didn't cross to the next tick");
  });

  it("pool2 - should execute trade and cross one tick - zero for one", async () => {
    // first push price into a range with 2 lp positions
    await bento.transfer(
      usd.address,
      alice.address,
      pool2.address,
      getBigNumber(1000)
    );
    let swapData = ethers.utils.defaultAbiCoder.encode(
      ["bool", "uint256", "address", "bool"],
      [false, getBigNumber(1000), alice.address, false]
    );
    await pool2.swap(swapData);

    const oldLiq = await pool2.liquidity();
    const oldTick = await pool2.nearestTick();
    const nextTick = (await pool2.ticks(oldTick)).nextTick;
    const oldEthBalance = await bento.balanceOf(weth.address, alice.address);
    const oldUSDBalance = await bento.balanceOf(usd.address, alice.address);
    const oldPrice = await pool2.price();

    await bento.transfer(
      weth.address,
      alice.address,
      pool2.address,
      getBigNumber(1)
    );
    swapData = ethers.utils.defaultAbiCoder.encode(
      ["bool", "uint256", "address", "bool"],
      [true, getBigNumber(1), alice.address, false] // sell 1 weth
    );
    await pool2.swap(swapData);

    const newLiq = await pool2.liquidity();
    const newPrice = await pool2.price();
    const newTick = await pool2.nearestTick();
    const usdReceived = (await bento.balanceOf(usd.address, alice.address)).sub(
      oldUSDBalance
    );
    const ethPaid = oldEthBalance.sub(
      await bento.balanceOf(weth.address, alice.address)
    );
    const tradePrice = parseInt(usdReceived.mul(100000).div(ethPaid)) / 100000;
    const tradePriceSqrtX96 = getSqrtX96Price(tradePrice);

    expect(ethPaid.eq(getBigNumber(1))).to.be.eq(true, "Didn't sell one eth");
    expect(usdReceived.gt(0)).to.be.eq(true, "Didn't get any usd");
    expect(oldPrice.gt(tradePriceSqrtX96)).to.be.eq(
      true,
      "Trade price isnt't lower than starting price"
    );
    expect(newPrice.lt(tradePriceSqrtX96)).to.be.eq(
      true,
      "New price isn't lower than trade prie"
    );
    expect(newTick < oldTick).to.be.eq(true, "We didn't drop down a tick");
    expect(oldPrice.gt(newPrice)).to.be.eq(true, "Price didn't increase");
    expect(oldLiq.gt(newLiq)).to.be.eq(
      true,
      "We didn't cross out of one position"
    );
  });
});

// todo add test for swapping outsite ticks where liquidity is 0

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

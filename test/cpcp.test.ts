// @ts-nocheck
import { ethers } from "hardhat";
import { getBigNumber } from "./utilities";
import { expect } from "chai";
import { ERC20Mock } from "../typechain/ERC20Mock";
import { Cpcp } from "../typechain/Cpcp";
import { Signer } from "crypto";

describe("Constant product concentrated pool (cpcp)", function () {
  let alice: Signer,
    weth: ERC20Mock,
    dai: ERC20Mock,
    daiWethPool: Cpcp,
    tickMath: TickMathTest;

  before(async function () {
    [alice] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");

    const CPCP = await ethers.getContractFactory("Cpcp");

    const TickMathTest = await ethers.getContractFactory("TickMathTest");

    const totalSupply = getBigNumber("100000000");

    weth = await ERC20.deploy("WETH", "ETH", totalSupply);
    dai = await ERC20.deploy("DAI", "DAI", totalSupply);

    tickMath = await TickMathTest.deploy();

    const sqrtPrice = "1807174424252647735792984898";
    // divided by 2**96 equals 0.02280974803
    // squared and inverted this is 1922.02 (price of eth in dai)
    // corresponds to tick -75616

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint160"],
      [dai.address, weth.address, sqrtPrice] // dai is token0 (x)
    );

    daiWethPool = await CPCP.deploy(deployData);

    await weth.approve(daiWethPool.address, totalSupply);

    await dai.approve(daiWethPool.address, totalSupply);
  });

  it("Should initialize correctly", async () => {
    const min = -887272;
    const max = 887272;

    const minTick = await daiWethPool.ticks(min);
    const maxTick = await daiWethPool.ticks(max);

    expect(minTick.previousTick).to.be.eq(min);
    expect(minTick.nextTick).to.be.eq(max);
    expect(maxTick.previousTick).to.be.eq(min);
    expect(maxTick.nextTick).to.be.eq(max);

    expect(await daiWethPool.liquidity()).to.be.eq(0);
  });

  it("Should add liquidity inside price range", async () => {
    // current price is 1920 dai per eth ... mint liquidity from ~1000 to ~3000
    const lower = -80068; // 0.000333 dai per eth
    const upper = -69081; // 0.001 dai per eth

    const currentPrice = await daiWethPool.sqrtPriceX96();
    const startingLiquidity = await daiWethPool.liquidity();

    const dy = getBigNumber(1);

    let dP = currentPrice.sub(await tickMath.getSqrtRatioAtTick(lower));

    const liquidity = dy.mul("0x1000000000000000000000000").div(dP);

    await daiWethPool.mint(-887272, lower, lower, upper, liquidity);

    expect((await daiWethPool.liquidity()).toString()).to.be.eq(
      liquidity.add(startingLiquidity).toString(),
      "Didn't add right amount of liquidity"
    );
    expect((await dai.balanceOf(daiWethPool.address)).toString()).to.be.eq(
      "2683758334569795392629",
      "Didn't calculate token0 (dx) amount correctly"
    );
    expect((await weth.balanceOf(daiWethPool.address)).toString()).to.be.eq(
      dy.toString(),
      "Didn't calculate token1 (dy) amount correctly"
    );
  });
});

describe.only("Constant product concentrated pool (cpcp) trading", function () {
  let alice: Signer,
    weth: ERC20Mock,
    usd: ERC20Mock,
    daiWethPool: Cpcp,
    tickMath: TickMathTest;

  const totalSupply = getBigNumber("100000000");
  const priceMultiplier = ethers.BigNumber.from("0x1000000000000000000000000");

  before(async function () {
    [alice] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const CPCP = await ethers.getContractFactory("Cpcp");
    const TickMathTest = await ethers.getContractFactory("TickMathTest");

    weth = await ERC20.deploy("WETH", "ETH", totalSupply);
    usd = await ERC20.deploy("USD", "USD", totalSupply);

    tickMath = await TickMathTest.deploy();

    const sqrtPrice = ethers.BigNumber.from("50").mul(
      "0x1000000000000000000000000"
    ); // current eth price is $2500

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint160"],
      [weth.address, usd.address, sqrtPrice] // weth is token 0 (x)
    );

    daiWethPool = await CPCP.deploy(deployData);

    await weth.approve(daiWethPool.address, totalSupply);
    await usd.approve(daiWethPool.address, totalSupply);

    // Current price is 2500, we are gonna mint liquidity on intervals ~ [1600, 3600] and ~ [2600, 3000]

    const lowerTick1 = 73780; // price 1599
    const lowerTick1Price = await tickMath.getSqrtRatioAtTick(lowerTick1);

    const upperTick1 = 81891; // price 3600
    const upperTick1Price = await tickMath.getSqrtRatioAtTick(upperTick1);

    const currentTick = 78244; // price 2500
    const currentTickPrice = await daiWethPool.sqrtPriceX96();

    const lowerTick2 = 78640; // price 2601
    const lowerTick2Price = await tickMath.getSqrtRatioAtTick(lowerTick2);

    const upperTick2 = 80149; // price ~3025
    const upperTick2Price = await tickMath.getSqrtRatioAtTick(upperTick2);

    // mint liquidity with 4k usd and x amount of eth
    // liquidity amount can be arbitrary for this test
    const liquidity = getBigNumber("4000")
      .mul(priceMultiplier)
      .div(currentTickPrice.sub(lowerTick1Price));

    await daiWethPool.mint(
      -887272,
      lowerTick1,
      lowerTick1,
      upperTick1,
      liquidity
    );

    await daiWethPool.mint(
      lowerTick1,
      lowerTick2,
      lowerTick2,
      upperTick2,
      liquidity
    );
  });

  it("Minter liquidity ticks in the right order", async () => {
    // check that the existing ticks & liquidity make sense
  });

  it("Should execute trade within current tick", async () => {
    const oldLiq = await daiWethPool.liquidity();
    const oldTick = await daiWethPool.nearestTick();

    expect(oldLiq.gt(0)).to.be.true;

    const oldPrice = await daiWethPool.sqrtPriceX96();

    // buy eth with 50 usd
    await daiWethPool.swap(false, getBigNumber(50), alice.address);

    const newPrice = await daiWethPool.sqrtPriceX96();
    const newTick = await daiWethPool.nearestTick();

    expect(oldTick).to.be.eq(newTick, "We crossed by mistake");
    expect(oldPrice.lt(newPrice)).to.be.true;
  });
});

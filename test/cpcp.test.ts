// @ts-nocheck
import { ethers } from "hardhat";
import { getBigNumber } from "./utilities";
import { expect } from "chai";
import { ERC20Mock } from "../typechain/ERC20Mock";
import { Cpcp } from "../typechain/Cpcp";
import { Signer } from "crypto";

describe.only("Constant product concentrated pool (cpcp)", function () {
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
    dai = await ERC20.deploy("SUSHI", "SUSHI", totalSupply);

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

// @ts-nocheck
import { ethers } from "hardhat";
import { getBigNumber } from "./utilities";
import { expect } from "chai";
import { ERC20Mock } from "../typechain/ERC20Mock";
import { Cpcp } from "../typechain/Cpcp";
import { Signer } from "crypto";

describe.only("Constant product concentrated pool (cpcp)", function () {

  let alice: Signer, weth: ERC20Mock, dai: ERC20Mock, daiWethPool: Cpcp;

  before(async function () {

    [alice] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const CPCP = await ethers.getContractFactory("Cpcp");
    const totalSupply = getBigNumber("100000000");

    weth = await ERC20.deploy("WETH", "ETH", totalSupply);
    dai = await ERC20.deploy("SUSHI", "SUSHI", totalSupply);

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

  it('Should initialize correctly', async () => {

    const minTick = await daiWethPool.ticks(887272);
    const maxTick = await daiWethPool.ticks(-887272);
    const liquidity = await daiWethPool.liquidity();

    expect(liquidity).to.be.eq(0);
    expect(minTick.exists).to.be.true;
    expect(maxTick.exists).to.be.true;
    expect(minTick.nextTick).to.be.eq(887272);

  });

  it('Should add liquidity inside price range', async () => {

    // current price is 1920 dai per eth ... mint liquidity from 1000 to 3000

    const dy = getBigNumber(1);
    console.log('price', (await daiWethPool.sqrtPriceX96()).toString());
    const liquidity = dy.div()

    const lower = -80068; // 0.000333 dai per eth
    const upper = -69081; // 0.001 dai per eth

    await daiWethPool.mint(-887272, lower, lower, upper, getBigNumber(100));

    console.log((await daiWethPool.liquidity()).toString());
    console.log((await weth.balanceOf(daiWethPool.address)).toString());
    console.log((await dai.balanceOf(daiWethPool.address)).toString());

  });

});
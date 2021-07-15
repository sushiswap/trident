import { ethers } from "hardhat";
import { getBigNumber } from "./utilities"

describe.only("Constant product concentrated pool (cpcp)", function () {

  let alice, weth, dai, daiWethPool: any;

  before(async function () {

    [alice] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const CPCP = await ethers.getContractFactory("Cpcp");

    weth = await ERC20.deploy("WETH", "ETH", getBigNumber("10000000"));
    dai = await ERC20.deploy("SUSHI", "SUSHI", getBigNumber("10000000"));

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address"],
      [weth.address, dai.address]
    );

    daiWethPool = await CPCP.deploy(deployData);

  });

  it.only('Should initialize correctly', async () => {

    console.log(daiWethPool.address);

  });

});
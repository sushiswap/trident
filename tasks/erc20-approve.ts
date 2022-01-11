import { task } from "hardhat/config";
import { constants } from "ethers";

const { MaxUint256 } = constants;

task("erc20:approve", "ERC20 approve")
  .addParam("token", "Token")
  .addParam("spender", "Spender")
  .setAction(async function ({ token, spender }, { ethers }, runSuper) {
    const dev = await ethers.getNamedSigner("dev");
    const erc20 = await ethers.getContractFactory("ERC20Mock");

    const slp = erc20.attach(token);

    await (await slp.connect(dev).approve(spender, MaxUint256)).wait();
  });

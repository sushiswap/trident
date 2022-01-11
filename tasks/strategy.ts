import { BENTOBOX_ADDRESS, ChainId, WETH9_ADDRESS } from "@sushiswap/core-sdk";
import { task } from "hardhat/config";

// misc helpers for testing purposes
task("add:strategy", "Add strategy to BentoBox")
  .addParam("bento", "BentoBox address", BENTOBOX_ADDRESS[ChainId.KOVAN])
  .addParam("token", "Token of strategy", WETH9_ADDRESS[ChainId.KOVAN])
  .addParam("strategy", "Strategy", "0x65E58C475e6f9CeF0d79371cC278E7827a72b19b")
  .setAction(async function ({ bento, token, strategy }, { ethers, getChainId }) {
    const dev = await ethers.getNamedSigner("dev");
    const chainId = await getChainId();
    const BentoBox = await ethers.getContractFactory("BentoBoxV1");

    let bentoBox;
    try {
      const _bentoBox = await ethers.getContract("BentoBoxV1");
      bentoBox = BentoBox.attach(_bentoBox.address);
    } catch ({}) {
      bentoBox = BentoBox.attach(BENTOBOX_ADDRESS[chainId]);
    }

    await bentoBox.connect(dev).setStrategy(token, strategy);
    await bentoBox.connect(dev).setStrategy(token, strategy); // testing version of bentobox has a strategy delay of 0
    await bentoBox.connect(dev).setStrategyTargetPercentage(token, "70");
  });

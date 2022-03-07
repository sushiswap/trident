import { BENTOBOX_ADDRESS, ChainId, WETH9_ADDRESS } from "@sushiswap/core-sdk";
import type { BentoBoxV1, BentoBoxV1__factory } from "../types";

import { task } from "hardhat/config";

task("add-strategy", "Add strategy to BentoBox")
  .addOptionalParam("bentoBox", "BentoBox address", BENTOBOX_ADDRESS[ChainId.KOVAN])
  .addOptionalParam("token", "Token of strategy", WETH9_ADDRESS[ChainId.KOVAN])
  .addOptionalParam("strategy", "Strategy", "0x65E58C475e6f9CeF0d79371cC278E7827a72b19b")
  .setAction(async function (
    { bentoBox, token, strategy }: { bentoBox: BentoBoxV1; token: string; strategy: string },
    { ethers, getChainId, deployments }
  ) {
    const dev = await ethers.getNamedSigner("dev");
    const chainId = await getChainId();
    const BentoBox = await ethers.getContractFactory<BentoBoxV1__factory>("BentoBoxV1");
    bentoBox = (await ethers.getContractOrNull<BentoBoxV1>("BentoBoxV1")) ?? BentoBox.attach(BENTOBOX_ADDRESS[chainId]);
    await bentoBox.connect(dev).setStrategy(token, strategy);
    await bentoBox.connect(dev).setStrategy(token, strategy); // testing version of bentobox has a strategy delay of 0
    await bentoBox.connect(dev).setStrategyTargetPercentage(token, "70");
  });

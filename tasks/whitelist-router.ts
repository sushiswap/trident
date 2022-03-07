import type { BentoBoxV1, BentoBoxV1__factory, TridentRouter } from "../types";

import { BENTOBOX_ADDRESS } from "@sushiswap/core-sdk";
import { task } from "hardhat/config";

task("whitelist", "Whitelist Router on BentoBox").setAction(async function (_, { ethers, getChainId }) {
  const dev = await ethers.getNamedSigner("dev");

  const chainId = await getChainId();

  const router = await ethers.getContract<TridentRouter>("TridentRouter");

  const BentoBox = await ethers.getContractFactory<BentoBoxV1__factory>("BentoBoxV1");

  let bentoBox: BentoBoxV1;
  try {
    bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
  } catch (error) {
    bentoBox = BentoBox.attach(BENTOBOX_ADDRESS[chainId]);
  }

  if (await bentoBox.whitelistedMasterContracts(router.address)) {
    console.log(`Whitelisted already on BentoBox (BentoBox: ${bentoBox.address})`);
  }

  if (!(await bentoBox.whitelistedMasterContracts(router.address))) {
    console.log(`Whitelisting master contract on BentoBox (BentoBox: ${bentoBox.address})`);
    await bentoBox
      .connect(dev)
      .whitelistMasterContract(router.address, true)
      .then((tx) => tx.wait());
    console.log(`Whitelisted master contract on BentoBox (BentoBox: ${bentoBox.address})`);
  }
});

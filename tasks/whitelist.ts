import { BENTOBOX_ADDRESS } from "@sushiswap/core-sdk";
import { task } from "hardhat/config";

task("whitelist", "Whitelist Router on BentoBox").setAction(async function (_, { ethers, getChainId }) {
  const dev = await ethers.getNamedSigner("dev");

  const chainId = await getChainId();

  const router = await ethers.getContract("TridentRouter");

  const BentoBox = await ethers.getContractFactory("BentoBoxV1");

  let bentoBox;

  try {
    const _bentoBox = await ethers.getContract("BentoBoxV1");
    bentoBox = BentoBox.attach(_bentoBox.address);
  } catch ({}) {
    bentoBox = BentoBox.attach(BENTOBOX_ADDRESS[chainId]);
  }

  await (await bentoBox.connect(dev).whitelistMasterContract(router.address, true)).wait();

  console.log(`Router successfully whitelisted on BentoBox (BentoBox: ${bentoBox.address})`);
});

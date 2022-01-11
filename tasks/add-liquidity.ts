import { BENTOBOX_ADDRESS, ChainId, WETH9_ADDRESS, USDC_ADDRESS } from "@sushiswap/core-sdk";
import { BigNumber } from "ethers";
import { task, types } from "hardhat/config";

task("add-liquidity", "Add liquidity")
  .addOptionalParam("tokenA", "Token A", WETH9_ADDRESS[ChainId.KOVAN], types.string)
  .addOptionalParam("tokenB", "Token B", USDC_ADDRESS[ChainId.KOVAN], types.string)
  // Probably don't need this, can compute from tokens
  .addParam("pool", "Pool")
  .addParam("tokenADesired", "Token A Desired", BigNumber.from(10).pow(18).toString(), types.string)
  .addParam("tokenBDesired", "Token B Desired", BigNumber.from(10).pow(6).toString(), types.string)
  // .addParam("tokenAMinimum", "Token A Minimum")
  // .addParam("tokenBMinimum", "Token B Minimum")
  // .addParam("to", "To")
  // .addOptionalParam("deadline", "Deadline", MaxUint256)
  .setAction(async function ({ tokenA, tokenB, pool }, { ethers, run, getChainId }, runSuper) {
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

    const dev = await ethers.getNamedSigner("dev");

    let liquidityInput = [
      {
        token: tokenA,
        native: false,
        amount: ethers.BigNumber.from(10).pow(9),
      },
      {
        token: tokenB,
        native: false,
        amount: ethers.BigNumber.from(10).pow(6),
      },
    ];

    await (await bentoBox.connect(dev).whitelistMasterContract(router.address, true)).wait();
    console.log("Whitelisted master contract");

    await run("erc20:approve", {
      token: liquidityInput[0].token,
      spender: bentoBox.address,
    });

    await run("erc20:approve", {
      token: liquidityInput[1].token,
      spender: bentoBox.address,
    });

    console.log("Approved both tokens");

    console.log("Depositing 1st token", [liquidityInput[0].token, dev.address, dev.address, 0, liquidityInput[0].amount]);
    await (await bentoBox.connect(dev).deposit(liquidityInput[0].token, dev.address, dev.address, 0, liquidityInput[0].amount)).wait();
    console.log("Depositing 2nd token");
    await (await bentoBox.connect(dev).deposit(liquidityInput[1].token, dev.address, dev.address, 0, liquidityInput[1].amount)).wait();

    console.log("Deposited");

    await (await bentoBox.connect(dev).deposit(liquidityInput[0].token, dev.address, dev.address, 0, liquidityInput[0].amount)).wait();
    await (await bentoBox.connect(dev).deposit(liquidityInput[1].token, dev.address, dev.address, 0, liquidityInput[1].amount)).wait();

    console.log("Deposited");

    await (
      await bentoBox
        .connect(dev)
        .setMasterContractApproval(
          dev.address,
          router.address,
          true,
          "0",
          "0x0000000000000000000000000000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000000000000000000000000000"
        )
    ).wait();

    console.log("Set master contract approval");

    const data = ethers.utils.defaultAbiCoder.encode(["address"], [dev.address]);

    await (await router.connect(dev).addLiquidity(liquidityInput, pool, 1, data)).wait();

    console.log("Added liquidity");
  });

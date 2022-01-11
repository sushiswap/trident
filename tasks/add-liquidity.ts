import { BENTOBOX_ADDRESS, ChainId, WETH9_ADDRESS, USDC_ADDRESS } from "@sushiswap/core-sdk";
import { ethers } from "ethers";
import { task, types } from "hardhat/config";
import { BentoBoxV1, BentoBoxV1__factory, ERC20Mock, TridentRouter } from "../types";

const { BigNumber } = ethers;

task("add-liquidity", "Add liquidity")
  .addOptionalParam("tokenA", "Token A", WETH9_ADDRESS[ChainId.KOVAN], types.string)
  .addOptionalParam("tokenB", "Token B", USDC_ADDRESS[ChainId.KOVAN], types.string)
  .addOptionalParam("pool", "Pool")
  .addOptionalParam("minLiquidity", "Minimum Liquidity", BigNumber.from(10).pow(1).toString(), types.string)
  .addOptionalParam("recipient", "Recipient", "0xd198B08Fb9bfd659065D3c15FbcE14e44Ab54D42", types.string) // dev default
  .setAction(
    async (
      {
        tokenA,
        tokenB,
        pool,
        minLiquidity,
        recipient,
      }: { tokenA: string; tokenB: string; pool?: string; minLiquidity: number; recipient: string },
      { ethers, run, getChainId, getNamedAccounts },
      runSuper
    ) => {
      const chainId = await getChainId();

      pool = pool || ((await run("cpp-address")) as string);

      const { deployer } = await getNamedAccounts();

      const router = await ethers.getContract<TridentRouter>("TridentRouter");

      const BentoBox = await ethers.getContractFactory<BentoBoxV1__factory>("BentoBoxV1");

      let bentoBox: BentoBoxV1;

      try {
        bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      } catch (error) {
        bentoBox = BentoBox.attach(BENTOBOX_ADDRESS[chainId]);
      }

      const dev = await ethers.getNamedSigner("dev");

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", tokenA);

      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", tokenB);

      let liquidityInput = [
        {
          token: token0.address,
          native: true,
          amount: ethers.BigNumber.from(10).pow(3),
        },
        {
          token: token1.address,
          native: true,
          amount: ethers.BigNumber.from(10).pow(6),
        },
      ];

      await run("whitelist");

      if ((await token0.allowance(deployer, bentoBox.address)).lt(liquidityInput[0].amount)) {
        await run("erc20:approve", {
          token: liquidityInput[0].token,
          spender: bentoBox.address,
        });
      }

      if ((await token1.allowance(deployer, bentoBox.address)).lt(liquidityInput[1].amount)) {
        await run("erc20:approve", {
          token: liquidityInput[1].token,
          spender: bentoBox.address,
        });
      }
      console.log("Approved both tokens");

      console.log("Depositing 1st token", [liquidityInput[0].token, dev.address, dev.address, 0, liquidityInput[0].amount]);
      await bentoBox
        .connect(dev)
        .deposit(liquidityInput[0].token, dev.address, dev.address, 0, liquidityInput[0].amount)
        .then((tx) => tx.wait());

      console.log("Depositing 2nd token");
      await bentoBox
        .connect(dev)
        .deposit(liquidityInput[1].token, dev.address, dev.address, 0, liquidityInput[1].amount)
        .then((tx) => tx.wait());

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
        .then((tx) => tx.wait());

      console.log("Set master contract approval");

      const data = ethers.utils.defaultAbiCoder.encode(["address"], [recipient]);

      console.log(`Adding minmimum of ${minLiquidity} liquidity to ${pool}`);

      await router
        .connect(dev)
        .addLiquidity(liquidityInput, pool, minLiquidity, data)
        .then((tx) => tx.wait());

      console.log("Added liquidity");
    }
  );

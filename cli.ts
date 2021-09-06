import { BENTOBOX_ADDRESS, ChainId } from "@sushiswap/sdk";
import { BigNumber, constants } from "ethers";
import { task, types } from "hardhat/config";

const { MaxUint256 } = constants;

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, { ethers }) => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.address);
  }
});

task("erc20:approve", "ERC20 approve")
  .addParam("token", "Token")
  .addParam("spender", "Spender")
  .setAction(async function ({ token, spender }, { ethers }, runSuper) {
    const dev = await ethers.getNamedSigner("dev");
    const erc20 = await ethers.getContractFactory("ERC20Mock");

    const slp = erc20.attach(token);

    await (await slp.connect(dev).approve(spender, MaxUint256)).wait();
  });

task("constant-product-pool:deploy", "Constant Product Pool deploy")
  .addOptionalParam(
    "tokena",
    "Token A",
    "0x4f96fe3b7a6cf9725f59d353f723c1bdb64ca6aa", // dai
    types.string
  )
  .addOptionalParam(
    "tokenb",
    "Token B",
    "0xd0A1E359811322d97991E03f863a0C30C2cF029C", // weth
    types.string
  )
  .addOptionalParam("fee", "Fee tier", 30, types.int)
  .addOptionalParam("twap", "Twap enabled", false, types.boolean)
  .setAction(async function (
    { tokena, tokenb, fee, twap },
    { ethers },
    runSuper
  ) {
    const masterDeployer = await ethers.getContract("MasterDeployer");

    const constantProductPoolFactory = await ethers.getContract(
      "ConstantProductPoolFactory"
    );

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint8", "bool"],
      [...[tokena, tokenb].sort(), fee, twap]
    );

    const { events } = await (
      await masterDeployer.deployPool(
        constantProductPoolFactory.address,
        deployData
      )
    ).wait();

    console.log(events);
  });

task("whitelist", "Whitelist Router on BentoBox").setAction(async function (
  _,
  { ethers, getChainId }
) {
  const deployer = await ethers.getNamedSigner("deployer");

  const chainId = await getChainId();

  const router = await ethers.getContract("TridentRouter");

  const BentoBox = await ethers.getContractFactory("BentoBoxV1");
  const bentoBox = BentoBox.attach(
    "0x2bf45480039C609e3a73A37eE09A1CB157c99c6C" || BENTOBOX_ADDRESS[chainId]
  );

  await (
    await bentoBox
      .connect(deployer)
      .whitelistMasterContract(router.address, true)
  ).wait();

  console.log("Router successfully whitelisted on BentoBox");
});

task("router:add-liquidity", "Router add liquidity")
  .addOptionalParam(
    "tokena",
    "Token A",
    "0x4f96fe3b7a6cf9725f59d353f723c1bdb64ca6aa", // dai
    types.string
  )
  .addOptionalParam(
    "tokenb",
    "Token B",
    "0xd0A1E359811322d97991E03f863a0C30C2cF029C", // weth
    types.string
  )
  .addOptionalParam(
    "pool",
    "Pool",
    "0x00928AB3c14ECc1C794867d9Ead734328A19D97b", // dai/weth
    types.string
  )
  .addOptionalParam(
    "bento",
    "BentoBox",
    "0x2bf45480039C609e3a73A37eE09A1CB157c99c6C", // kovan
    types.string
  )
  .addParam(
    "tokenADesired",
    "Token A Desired",
    BigNumber.from(10).pow(18).toString(),
    types.string
  )
  .addParam(
    "tokenBDesired",
    "Token B Desired",
    BigNumber.from(10).pow(18).toString(),
    types.string
  )
  // .addParam("tokenAMinimum", "Token A Minimum")
  // .addParam("tokenBMinimum", "Token B Minimum")
  // .addParam("to", "To")
  // .addOptionalParam("deadline", "Deadline", MaxUint256)
  .setAction(async function (
    { tokena, tokenb, pool, bento },
    { ethers, run, getChainId },
    runSuper
  ) {
    const chainId = await getChainId();

    const router = await ethers.getContract("TridentRouter");

    const BentoBox = await ethers.getContractFactory("BentoBoxV1");
    const bentoBox = BentoBox.attach(bento || BENTOBOX_ADDRESS[chainId]);

    const dev = await ethers.getNamedSigner("dev");

    const erc20 = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await erc20.attach(tokena);
    const tokenB = await erc20.attach(tokenb);

    let liquidityInput = [
      {
        token: tokena,
        native: false,
        amount: (await tokenA.balanceOf(dev.address)).toString(),
      },
      {
        token: tokenb,
        native: false,
        amount: (await tokenB.balanceOf(dev.address)).toString(),
      },
    ];

    await run("erc20:approve", {
      token: tokena,
      spender: bentoBox.address,
    });

    await run("erc20:approve", {
      token: tokenb,
      spender: bentoBox.address,
    });

    console.log("Approved both tokens");

    await (
      await bentoBox
        .connect(dev)
        .deposit(
          liquidityInput[0].token,
          dev.address,
          dev.address,
          liquidityInput[0].amount,
          0
        )
    ).wait();
    await (
      await bentoBox
        .connect(dev)
        .deposit(
          liquidityInput[1].token,
          dev.address,
          dev.address,
          liquidityInput[1].amount,
          0
        )
    ).wait();

    console.log("Deposited");

    await bentoBox
      .connect(dev)
      .setMasterContractApproval(
        dev.address,
        router.address,
        true,
        "0",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      );
    console.log("Set master contract approval");

    const data = ethers.utils.defaultAbiCoder.encode(
      ["address"],
      [dev.address]
    );

    await (
      await router.connect(dev).addLiquidity(liquidityInput, pool, 1, data)
    ).wait();

    console.log("Added liquidity");
  });

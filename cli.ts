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
    const erc20 = await ethers.getContractFactory("TridentERC20");

    const slp = erc20.attach(token);

    await (await slp.connect(dev).approve(spender, MaxUint256)).wait();
  });

task("constant-product-pool:deploy", "Constant Product Pool deploy")
  .addOptionalParam(
    "tokenA",
    "Token A",
    "0xc778417E063141139Fce010982780140Aa0cD5Ab",
    types.string
  )
  .addOptionalParam(
    "tokenB",
    "Token B",
    "0xc2118d4d90b274016cB7a54c03EF52E6c537D957",
    types.string
  )
  .addOptionalParam("fee", "Fee tier", 30, types.int)
  .addOptionalParam("twap", "Twap enabled", true, types.boolean)
  .setAction(async function (
    { tokenA, tokenB, fee, twap },
    { ethers },
    runSuper
  ) {
    const masterDeployer = await ethers.getContract("MasterDeployer");

    const constantProductPoolFactory = await ethers.getContract(
      "ConstantProductPoolFactory"
    );

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint8", "bool"],
      [...[tokenA, tokenB].sort(), fee, twap]
    );

    const { events } = await (
      await masterDeployer.deployPool(
        constantProductPoolFactory.address,
        deployData
      )
    ).wait();

    console.log(events);
  });

task("router:add-liquidity", "Router add liquidity")
  .addOptionalParam(
    "tokenA",
    "Token A",
    "0xc778417E063141139Fce010982780140Aa0cD5Ab",
    types.string
  )
  .addOptionalParam(
    "tokenB",
    "Token B",
    "0xc2118d4d90b274016cB7a54c03EF52E6c537D957",
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
  .setAction(async function (args, { ethers, run }, runSuper) {
    const router = await ethers.getContract("TridentRouter");
    const BentoBox = await ethers.getContractFactory("BentoBoxV1");
    const bentoBox = BentoBox.attach(BENTOBOX_ADDRESS[ChainId.ROPSTEN]);

    const dev = await ethers.getNamedSigner("dev");
    const pool = "0x735C2c1564C0230041Ef8CA5A6F7e74bab8C3dcA"; // dai/weth

    let liquidityInput = [
      {
        token: "0xc778417E063141139Fce010982780140Aa0cD5Ab", // weth
        native: false,
        amount: ethers.BigNumber.from(10).pow(17),
      },
      {
        token: "0xc2118d4d90b274016cB7a54c03EF52E6c537D957", // dai
        native: false,
        amount: ethers.BigNumber.from(10).pow(17),
      },
    ];

    await (
      await bentoBox.connect(dev).whitelistMasterContract(router.address, true)
    ).wait();
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

    await (
      await bentoBox
        .connect(dev)
        .deposit(
          liquidityInput[0].token,
          dev.address,
          dev.address,
          BigNumber.from(10).pow(17),
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
          BigNumber.from(10).pow(17),
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

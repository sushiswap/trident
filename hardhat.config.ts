import "dotenv/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-solhint";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "hardhat-gas-reporter";
import "hardhat-interface-generator";
import "hardhat-spdx-license-identifier";
import "hardhat-watcher";
import "solidity-coverage";
import "@tenderly/hardhat-tenderly";
import "@typechain/hardhat";
import "hardhat-tracer";

import { BENTOBOX_ADDRESS, ChainId } from "@sushiswap/sdk";
import { BigNumber, constants } from "ethers";
import { HardhatUserConfig, task, types } from "hardhat/config";

import { removeConsoleLog } from "hardhat-preprocessor";

const { MaxUint256 } = constants;

const accounts = {
  mnemonic:
    process.env.MNEMONIC ||
    "test test test test test test test test test test test junk",
};

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
    const pool = "0xda0D635F77b4a005A1E15ED02F6ad656DBd6FA02"; // dai/weth

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

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    currency: "USD",
    enabled: process.env.REPORT_GAS === "true",
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    dev: {
      default: 1,
    },
    alice: {
      default: 2,
    },
    bob: {
      default: 3,
    },
    carol: {
      default: 4,
    },
    dave: {
      default: 5,
    },
    eve: {
      default: 6,
    },
    feeTo: {
      default: 7,
    },
  },
  networks: {
    localhost: {
      live: false,
      saveDeployments: true,
      tags: ["local"],
    },
    hardhat: {
      forking: {
        enabled: process.env.FORKING === "true",
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      },
      allowUnlimitedContractSize: true,
      live: false,
      saveDeployments: true,
      tags: ["test", "local"],
    },
    ropsten: {
      url: `https://ropsten.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts,
      chainId: 3,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasPrice: 5000000000,
      gasMultiplier: 2,
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts,
      chainId: 4,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasPrice: 5000000000,
      gasMultiplier: 2,
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts,
      chainId: 5,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasPrice: 5000000000,
      gasMultiplier: 2,
    },
    kovan: {
      url: `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts,
      chainId: 42,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasPrice: 20000000000,
      gasMultiplier: 2,
    },
    fantom: {
      url: "https://rpcapi.fantom.network",
      accounts,
      chainId: 250,
      live: true,
      saveDeployments: true,
      gasPrice: 22000000000,
    },
    matic: {
      url: "https://rpc-mainnet.maticvigil.com",
      accounts,
      chainId: 137,
      live: true,
      saveDeployments: true,
    },
    "matic-testnet": {
      url: "https://rpc-mumbai.maticvigil.com/",
      accounts,
      chainId: 80001,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasMultiplier: 2,
    },
    xdai: {
      url: "https://rpc.xdaichain.com",
      accounts,
      chainId: 100,
      live: true,
      saveDeployments: true,
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org",
      accounts,
      chainId: 56,
      live: true,
      saveDeployments: true,
    },
    "bsc-testnet": {
      url: "https://data-seed-prebsc-2-s3.binance.org:8545",
      accounts,
      chainId: 97,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasMultiplier: 2,
    },
    heco: {
      url: "https://http-mainnet.hecochain.com",
      accounts,
      chainId: 128,
      live: true,
      saveDeployments: true,
    },
    "heco-testnet": {
      url: "https://http-testnet.hecochain.com",
      accounts,
      chainId: 256,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasMultiplier: 2,
    },
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts,
      chainId: 43114,
      live: true,
      saveDeployments: true,
      gasPrice: 470000000000,
    },
    "avalanche-testnet": {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts,
      chainId: 43113,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasMultiplier: 2,
    },
    harmony: {
      url: "https://api.s0.t.hmny.io",
      accounts,
      chainId: 1666600000,
      live: true,
      saveDeployments: true,
    },
    "harmony-testnet": {
      url: "https://api.s0.b.hmny.io",
      accounts,
      chainId: 1666700000,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasMultiplier: 2,
    },
    okex: {
      url: "https://exchainrpc.okex.org",
      accounts,
      chainId: 66,
      live: true,
      saveDeployments: true,
    },
    "okex-testnet": {
      url: "https://exchaintestrpc.okex.org",
      accounts,
      chainId: 65,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasMultiplier: 2,
    },
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts,
      chainId: 42161,
      live: true,
      saveDeployments: true,
      blockGasLimit: 700000,
    },
    "arbitrum-testnet": {
      url: "https://kovan3.arbitrum.io/rpc",
      accounts,
      chainId: 79377087078960,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      gasMultiplier: 2,
    },
    celo: {
      url: "https://forno.celo.org",
      accounts,
      chainId: 42220,
      live: true,
      saveDeployments: true,
    },
  },
  paths: {
    artifacts: "artifacts",
    cache: "cache",
    deploy: "deploy",
    deployments: "deployments",
    imports: "imports",
    sources: "contracts",
    tests: "test",
  },
  preprocess: {
    eachLine: removeConsoleLog(
      (bre) =>
        bre.network.name !== "hardhat" && bre.network.name !== "localhost"
    ),
  },
  solidity: {
    compilers: [
      {
        version: "0.8.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 99999,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 99999,
          },
        },
      },
      {
        version: "0.4.19",
        settings: {
          optimizer: {
            enabled: false,
            runs: 200,
          },
        },
      },
    ],
  },
  tenderly: {
    project: process.env.TENDERLY_PROJECT || "",
    username: process.env.TENDERLY_USERNAME || "",
  },
  typechain: {
    outDir: "types",
    target: "ethers-v5",
  },
  watcher: {
    compile: {
      tasks: ["compile"],
      files: ["./contracts"],
      verbose: true,
    },
  },
  mocha: {
    timeout: 300000,
    bail: true,
  },
};

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
export default config;

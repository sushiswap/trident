import { BigNumber } from "ethers";
import { ethers, deployments } from "hardhat";
import {
  BentoBoxV1,
  StablePoolFactory,
  StablePool__factory,
  ERC20Mock__factory,
  MasterDeployer,
  ERC20Mock,
} from "../../../types";

export const initializedStablePool = deployments.createFixture(
  async (
    {
      deployments,
      ethers: {
        getNamedSigners,
        constants: { MaxUint256 },
      },
    },
    options?: {
      fee?: number;
      token0Decimals?: number;
      token1Decimals?: number;
    }
  ) => {
    options = {
      fee: 1,
      ...options,
    };

    await deployments.fixture(["StablePoolFactory"]); // ensure you start from a fresh deployments
    const { deployer } = await getNamedSigners();

    const ERC20 = await ethers.getContractFactory<ERC20Mock__factory>("ERC20Mock");

    let token0, token1;
    if (options.token0Decimals === undefined) {
      token0 = await ERC20.deploy("Token 0", "TOKEN0", ethers.constants.MaxUint256);
      await token0.deployed();
    } else {
      token0 = await ERC20.deploy(
        `Token0-${options.token0Decimals}`,
        `TOKEN0-${options.token0Decimals}`,
        ethers.constants.MaxUint256
      );
      token0.setDecimals(options.token0Decimals);
      await token0.deployed();
    }

    if (options.token1Decimals === undefined) {
      token1 = await ERC20.deploy("Token 1", "TOKEN1", ethers.constants.MaxUint256);
      await token1.deployed();
    } else {
      token1 = await ERC20.deploy(
        `Token1-${options.token1Decimals}`,
        `TOKEN1-${options.token1Decimals}`,
        ethers.constants.MaxUint256
      );
      token1.setDecimals(options.token1Decimals);
      await token0.deployed();
    }

    const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

    const stablePoolFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256"],
      [token0.address, token1.address, options.fee]
    );

    const contractReceipt = await masterDeployer
      .deployPool(stablePoolFactory.address, deployData)
      .then((tx) => tx.wait());

    const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

    await bento.whitelistMasterContract("0x0000000000000000000000000000000000000001", true);

    await token0.approve(bento.address, MaxUint256).then((tx) => tx.wait());
    await token1.approve(bento.address, MaxUint256).then((tx) => tx.wait());

    // To emulate base !== elastic
    const elastic = BigNumber.from(10).pow(18);
    await token0.transfer(bento.address, elastic);
    await bento.setTokenTotal(token0.address, elastic, elastic.mul(110).div(100));

    await bento
      .setMasterContractApproval(
        deployer.address,
        "0x0000000000000000000000000000000000000001",
        true,
        "0",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      )
      .then((tx) => tx.wait());

    await bento
      .deposit(token0.address, deployer.address, deployer.address, "1000000000000000000", 0)
      .then((tx) => tx.wait());

    await bento
      .deposit(token1.address, deployer.address, deployer.address, "1000000000000000000", 0)
      .then((tx) => tx.wait());

    await bento
      .transfer(token0.address, deployer.address, contractReceipt.events?.[0].args?.pool, "1000000000000000000")
      .then((tx) => tx.wait());

    await bento

      .transfer(token1.address, deployer.address, contractReceipt.events?.[0].args?.pool, "1000000000000000000")
      .then((tx) => tx.wait());

    const Pool = await ethers.getContractFactory<StablePool__factory>("StablePool");

    const pool = Pool.attach(contractReceipt.events?.[0].args?.pool);

    await pool.mint(ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address])).then((tx) => tx.wait());

    return pool;
  },
  "initializedStablePool"
);

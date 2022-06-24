import { ethers, deployments } from "hardhat";
import { StablePoolFactory, StablePool__factory, ERC20Mock__factory, MasterDeployer } from "../../../types";

export const uninitializedStablePool = deployments.createFixture(async ({ deployments, ethers }, options) => {
  await deployments.fixture(["StablePoolFactory"]); // ensure you start from a fresh deployments

  const ERC20 = await ethers.getContractFactory<ERC20Mock__factory>("ERC20Mock");

  const token0 = await ERC20.deploy("Token 0", "TOKEN0", ethers.constants.MaxUint256);
  await token0.deployed();

  const token1 = await ERC20.deploy("Token 1", "TOKEN1", ethers.constants.MaxUint256);
  await token1.deployed();

  const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

  const stablePoolFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");

  const deployData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "uint256"],
    [token0.address, token1.address, 0]
  );

  const contractReceipt = await masterDeployer
    .deployPool(stablePoolFactory.address, deployData)
    .then((tx) => tx.wait());

  const Pool = await ethers.getContractFactory<StablePool__factory>("StablePool");

  const pool = Pool.attach(contractReceipt.events?.[0].args?.pool);

  return pool;
}, "uninitializedStablePool");

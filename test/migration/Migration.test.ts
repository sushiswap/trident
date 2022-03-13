import { ethers, network } from "hardhat";
import { expect } from "chai";
import { customError } from "../utilities";
import { Migrator__factory, TridentSushiRollCP, TridentSushiRollCP__factory } from "../../types";

describe("Migration", function () {
  let _owner, owner, chef, migrator, usdcWethLp, usdc, weth, masterDeployer, factory, Pool, snapshotId, ERC20;

  let manualMigrator: TridentSushiRollCP;

  before(async () => {
    snapshotId = await ethers.provider.send("evm_snapshot", []);

    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
            blockNumber: 13390000,
          },
        },
      ],
    });

    _owner = "0x9a8541ddf3a932a9a922b607e9cf7301f1d47bd1"; // timelock, owner of MasterChef
    owner = await ethers.getSigner(_owner);
    const [alice] = await ethers.getSigners();
    const BentoBox = await ethers.getContractFactory("BentoBoxV1");
    const MasterDeployer = await ethers.getContractFactory("MasterDeployer");
    const Factory = await ethers.getContractFactory("ConstantProductPoolFactory");
    const ManualMigrator = await ethers.getContractFactory<TridentSushiRollCP__factory>("TridentSushiRollCP");
    const Migrator = await ethers.getContractFactory<Migrator__factory>("Migrator");
    Pool = await ethers.getContractFactory("ConstantProductPool");
    ERC20 = await ethers.getContractFactory("ERC20Mock");
    chef = await ethers.getContractAt(mcABI, "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd", owner);
    usdc = await ERC20.attach("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
    weth = await ERC20.attach("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    usdcWethLp = await ERC20.attach("0x397FF1542f962076d0BFE58eA045FfA2d347ACa0"); // pid 1

    await network.provider.send("hardhat_setBalance", [chef.address, "0x100000000000000000000"]);
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [chef.address],
    });
    await network.provider.send("hardhat_setBalance", [_owner, "0x100000000000000000000"]);
    await usdcWethLp.connect(await ethers.getSigner(chef.address)).transfer(_owner, "0xfffffffff"); // give some LP tokens to _owner for testing purposes
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [_owner],
    });

    const bentoBox = await BentoBox.deploy(weth.address);
    masterDeployer = await MasterDeployer.deploy(0, alice.address, bentoBox.address);
    factory = await Factory.deploy(masterDeployer.address);
    migrator = await Migrator.deploy(bentoBox.address, masterDeployer.address, factory.address, chef.address);
    manualMigrator = await ManualMigrator.deploy(bentoBox.address, factory.address, masterDeployer.address);

    await masterDeployer.addToWhitelist(factory.address);
    await chef.setMigrator(migrator.address);
  });

  it("Should prepare for migration in chef", async () => {
    const _migrator = await chef.migrator();
    expect(_migrator).to.be.eq(migrator.address);
  });

  it("Should migrate successfully from chef", async () => {
    const oldTotalSupply = await usdcWethLp.totalSupply();
    const oldUsdcBalance = await usdc.balanceOf(usdcWethLp.address);
    const oldWethBalance = await weth.balanceOf(usdcWethLp.address);
    const oldLpToken = (await chef.poolInfo(1)).lpToken;
    const mcBalance = await usdcWethLp.balanceOf(chef.address);
    expect(oldLpToken).to.be.eq(usdcWethLp.address, "We don't have the corect LP address");

    await chef.migrate(1);

    const newTotalSupply = await usdcWethLp.totalSupply();
    const newUsdcBalance = await usdc.balanceOf(usdcWethLp.address);
    const newWethBalance = await weth.balanceOf(usdcWethLp.address);
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256", "bool"],
      [usdc.address, weth.address, 30, false]
    );
    const salt = ethers.utils.keccak256(deployData);
    const pool = await Pool.attach(await factory.configAddress(salt));

    expect((await pool.totalSupply()).gt(0)).to.be.true;
    expect(oldTotalSupply.gt(newTotalSupply)).to.be.true;
    expect(oldUsdcBalance.gt(newUsdcBalance)).to.be.true;
    expect(oldWethBalance.gt(newWethBalance)).to.be.true;

    // we must not allow two calls for the same pool
    await expect(chef.migrate(1)).to.be.revertedWith("ONLY_ONCE");

    const _intermediaryToken = (await chef.poolInfo(1)).lpToken;
    expect(_intermediaryToken).to.not.be.eq(oldLpToken, "we dodn't swap out tokens in masterchef");

    const intermediaryToken = await ERC20.attach(_intermediaryToken);
    const intermediaryTokenBalance = await pool.balanceOf(_intermediaryToken);
    expect(intermediaryTokenBalance.gt(0)).to.be.true;

    const newMcBalance = await intermediaryToken.balanceOf(chef.address);
    expect(newMcBalance.toString()).to.be.eq(
      newMcBalance.toString(),
      "MC didn't receive the correct amount of the intermediary token"
    );
  });

  it("Should migrate uniswap v2 style Lp positions outside of MasterChef", async () => {
    // _owner has some usdc-weth lp coins we can migrate
    const balance = await usdcWethLp.balanceOf(_owner);
    usdcWethLp.connect(owner).approve(manualMigrator.address, balance);
    await expect(
      manualMigrator.connect(owner).migrate(usdcWethLp.address, balance.div(2), 30, false, balance, balance, balance)
    ).to.be.revertedWith(customError("MinimumOutput"));
    await manualMigrator.connect(owner).migrate(usdcWethLp.address, balance.div(2), 30, false, 0, 0, 0);
    const poolAddy = (await factory.getPools(usdc.address, weth.address, 0, 1))[0];
    const pool = await ERC20.attach(poolAddy);
    const newBalance = await pool.balanceOf(_owner);
    await manualMigrator.connect(owner).migrate(usdcWethLp.address, balance.div(2), 30, false, 0, 0, 0);
    expect(newBalance.gt(0)).to.be.true;
    expect((await pool.balanceOf(_owner)).gt(newBalance)).to.be.true;
  });

  after(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    });
    // disable forking and reset to not affect the wholes repo's test suite
    await network.provider.send("evm_revert", [snapshotId]);
  });
});

const mcABI = [
  {
    inputs: [{ internalType: "uint256", name: "_pid", type: "uint256" }],
    name: "migrate",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "migrator",
    outputs: [{ internalType: "contract IMigratorChef", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "contract IMigratorChef",
        name: "_migrator",
        type: "address",
      },
    ],
    name: "setMigrator",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    name: "poolInfo",
    outputs: [
      {
        internalType: "contract IERC20",
        name: "lpToken",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "allocPoint",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "lastRewardBlock",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "accSushiPerShare",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

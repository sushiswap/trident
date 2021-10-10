import { ethers, network } from "hardhat";
import { expect } from "chai";

describe.only("Migration", function () {
  let chef, migrator, usdcWethLp, usdc, weth, masterDeployer, factory, Pool;

  before(async () => {
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

    const [alice] = await ethers.getSigners();
    const _owner = "0x9a8541ddf3a932a9a922b607e9cf7301f1d47bd1";
    const chefOwner = await ethers.getSigner(_owner);
    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const BentoBox = await ethers.getContractFactory("BentoBoxV1");
    const MasterDeployer = await ethers.getContractFactory("MasterDeployer");
    const Factory = await ethers.getContractFactory(
      "ConstantProductPoolFactory"
    );
    const Migrator = await ethers.getContractFactory("Migrator");
    Pool = await ethers.getContractFactory("ConstantProductPool");

    await network.provider.send("hardhat_setBalance", [
      _owner,
      "0x100000000000000000000",
    ]);
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [_owner],
    });

    chef = await ethers.getContractAt(
      mcABI,
      "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd",
      chefOwner
    );
    usdc = await ERC20.attach("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
    weth = await ERC20.attach("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    usdcWethLp = await ERC20.attach(
      "0x397FF1542f962076d0BFE58eA045FfA2d347ACa0"
    ); // pid 1

    const bentoBox = await BentoBox.deploy(weth.address);
    masterDeployer = await MasterDeployer.deploy(
      0,
      alice.address,
      bentoBox.address
    );
    factory = await Factory.deploy(masterDeployer.address);
    migrator = await Migrator.deploy(
      bentoBox.address,
      masterDeployer.address,
      factory.address,
      chef.address
    );

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
    await expect(chef.migrate(1)).to.be.revertedWith(
      "Transaction reverted: function selector was not recognized and there's no fallback function"
    );
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
    outputs: [
      { internalType: "contract IMigratorChef", name: "", type: "address" },
    ],
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
];

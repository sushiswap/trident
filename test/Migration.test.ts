// @ts-nocheck
 
import { getBigNumber } from "./utilities";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";
 
describe.only("Migration", function () {
  let chef1, chef2, migrator, usdcWethLp, cvxWethLp, usdc, cvx, weth;
 
  before(async () => {
    const [alice, feeTo] = await ethers.getSigners();
 
    const _owner = "0x9a8541ddf3a932a9a922b607e9cf7301f1d47bd1";
    const chefOwner = await ethers.getSigner(_owner);
 
    await network.provider.send("hardhat_setBalance", [
      _owner,
      "0x1000000000000000000",
    ]);
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [_owner],
    });
 
    chef1 = await ethers.getContractAt(
      mcABI,
      "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd",
      chefOwner
    );
    
    chef2 = await ethers.getContractAt(
      mcABI,
      "0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d",
      chefOwner
    );
 
    const ERC20 = await ethers.getContractFactory("ERC20Mock");
 
    usdc = await ERC20.attach("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
    cvx =  await ERC20.attach("0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B");
    weth = await ERC20.attach("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    usdcWethLp = await ERC20.attach(
      "0x397FF1542f962076d0BFE58eA045FfA2d347ACa0"
    );
    cvxWethLp = await ERC20.attach(
      "0x05767d9EF41dC40689678fFca0608878fb3dE906"
    );
 
    const BentoBox = await ethers.getContractFactory("BentoBoxV1");
    const bentoBox = await BentoBox.deploy(weth.address);
 
    const MasterDeployer = await ethers.getContractFactory("MasterDeployer");
    const masterDeployer = await MasterDeployer.deploy(
      0,
      feeTo.address,
      bentoBox.address
    );
 
    const Factory = await ethers.getContractFactory(
      "ConstantProductPoolFactory"
    );
    const factory = await Factory.deploy(masterDeployer.address);
 
    const Migrator = await ethers.getContractFactory("Migrator");
    migrator = await Migrator.deploy(
      bentoBox.address,
      factory.address,
      chef1.address,
      chef2.address
    );
 
    await chef1.setMigrator(migrator.address);
    await chef2.setMigrator(migrator.address);
    await masterDeployer.setMigrator(migrator.address);
  });
 
  it("Should prepare for migration in chef1", async () => {
    const _migrator = await chef1.migrator();
    expect(_migrator).to.be.eq(migrator.address);
  });
  
  it("Should prepare for migration in chef2", async () => {
    const _migrator = await chef2.migrator();
    expect(_migrator).to.be.eq(migrator.address);
  });
 
  it("Should migrate successfully from chef1", async () => {
    const oldTotalSupply = await usdcWethLp.totalSupply();
    const oldUsdcBalance = await usdc.balanceOf(usdcWethLp.address);
    const oldWethBalance = await weth.balanceOf(usdcWethLp.address);
 
    await chef1.migrate(1);
 
    const newTotalSupply = await usdcWethLp.totalSupply();
    const newUsdcBalance = await usdc.balanceOf(usdcWethLp.address);
    const newWethBalance = await weth.balanceOf(usdcWethLp.address);
 
    expect(oldTotalSupply.gt(newTotalSupply)).to.be.true;
    expect(oldUsdcBalance.gt(newUsdcBalance)).to.be.true;
    expect(oldWethBalance.gt(newWethBalance)).to.be.true;
  });
  
  it("Should migrate successfully from chef2", async () => {
    const oldTotalSupply = await cvxWethLp.totalSupply();
    const oldCvxBalance = await cvx.balanceOf(cvxWethLp.address);
    const oldWethBalance = await weth.balanceOf(cvxWethLp.address);
 
    await chef2.migrate(1);
 
    const newTotalSupply = await cvxWethLp.totalSupply();
    const newCvxBalance = await cvx.balanceOf(cvxWethLp.address);
    const newWethBalance = await weth.balanceOf(cvxWethLp.address);
 
    expect(oldTotalSupply.gt(newTotalSupply)).to.be.true;
    expect(oldCvxBalance.gt(newCvxBalance)).to.be.true;
    expect(oldWethBalance.gt(newWethBalance)).to.be.true;
  });
});
 
const mcABI = [
  {
    inputs: [
      { internalType: "contract SushiToken", name: "_sushi", type: "address" },
      { internalType: "address", name: "_devaddr", type: "address" },
      { internalType: "uint256", name: "_sushiPerBlock", type: "uint256" },
      { internalType: "uint256", name: "_startBlock", type: "uint256" },
      { internalType: "uint256", name: "_bonusEndBlock", type: "uint256" },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: "address", name: "user", type: "address" },
      { indexed: true, internalType: "uint256", name: "pid", type: "uint256" },
      {
        indexed: false,
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "Deposit",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: "address", name: "user", type: "address" },
      { indexed: true, internalType: "uint256", name: "pid", type: "uint256" },
      {
        indexed: false,
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "EmergencyWithdraw",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "previousOwner",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "newOwner",
        type: "address",
      },
    ],
    name: "OwnershipTransferred",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: "address", name: "user", type: "address" },
      { indexed: true, internalType: "uint256", name: "pid", type: "uint256" },
      {
        indexed: false,
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "Withdraw",
    type: "event",
  },
  {
    inputs: [],
    name: "BONUS_MULTIPLIER",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "uint256", name: "_allocPoint", type: "uint256" },
      { internalType: "contract IERC20", name: "_lpToken", type: "address" },
      { internalType: "bool", name: "_withUpdate", type: "bool" },
    ],
    name: "add",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "bonusEndBlock",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "uint256", name: "_pid", type: "uint256" },
      { internalType: "uint256", name: "_amount", type: "uint256" },
    ],
    name: "deposit",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "_devaddr", type: "address" }],
    name: "dev",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "devaddr",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "uint256", name: "_pid", type: "uint256" }],
    name: "emergencyWithdraw",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "uint256", name: "_from", type: "uint256" },
      { internalType: "uint256", name: "_to", type: "uint256" },
    ],
    name: "getMultiplier",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "massUpdatePools",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
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
    inputs: [],
    name: "owner",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "uint256", name: "_pid", type: "uint256" },
      { internalType: "address", name: "_user", type: "address" },
    ],
    name: "pendingSushi",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    name: "poolInfo",
    outputs: [
      { internalType: "contract IERC20", name: "lpToken", type: "address" },
      { internalType: "uint256", name: "allocPoint", type: "uint256" },
      { internalType: "uint256", name: "lastRewardBlock", type: "uint256" },
      { internalType: "uint256", name: "accSushiPerShare", type: "uint256" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "poolLength",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "renounceOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "uint256", name: "_pid", type: "uint256" },
      { internalType: "uint256", name: "_allocPoint", type: "uint256" },
      { internalType: "bool", name: "_withUpdate", type: "bool" },
    ],
    name: "set",
    outputs: [],
    stateMutability: "nonpayable",
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
    inputs: [],
    name: "startBlock",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "sushi",
    outputs: [
      { internalType: "contract SushiToken", name: "", type: "address" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "sushiPerBlock",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalAllocPoint",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "newOwner", type: "address" }],
    name: "transferOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "uint256", name: "_pid", type: "uint256" }],
    name: "updatePool",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "uint256", name: "", type: "uint256" },
      { internalType: "address", name: "", type: "address" },
    ],
    name: "userInfo",
    outputs: [
      { internalType: "uint256", name: "amount", type: "uint256" },
      { internalType: "uint256", name: "rewardDebt", type: "uint256" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "uint256", name: "_pid", type: "uint256" },
      { internalType: "uint256", name: "_amount", type: "uint256" },
    ],
    name: "withdraw",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];
 
/* (155,666,017.592427 * 47,019.46046482554355292)^0.5
1.584775554479133952 */

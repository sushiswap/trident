// @ts-nocheck

import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { getBigNumber } from "./utilities";

let alice,
  aliceEncoded,
  feeTo,
  weth,
  usdc,
  bento,
  masterDeployer,
  tridentPoolFactory,
  router,
  pool;

describe("Franchised pool", function () {
  before(async function () {
    await initialize();
  });

  it("Should add liquidity", async function () {
    const amount = BigNumber.from(10).pow(18);
    const expectedLiquidity = amount.sub(1000);
    let liquidityInput = [
      {
        token: weth.address,
        native: false,
        amount: amount,
      },
      {
        token: usdc.address,
        native: false,
        amount: amount,
      },
    ];
    let addLiquidityPromise = router.addLiquidity(
      liquidityInput,
      pool.address,
      1,
      aliceEncoded
    );
    await expect(addLiquidityPromise)
      .to.emit(pool, "Mint")
      .withArgs(
        router.address,
        liquidityInput[0].amount,
        liquidityInput[1].amount,
        alice.address,
        expectedLiquidity
      );

    let totalSupply = await pool.totalSupply();
    let wethPoolBalance = await bento.balanceOf(weth.address, pool.address);
    let usdcPoolBalance = await bento.balanceOf(usdc.address, pool.address);

    expect(totalSupply).eq(amount);
    expect(wethPoolBalance).eq(amount);
    expect(usdcPoolBalance).eq(amount);
  });
});

export async function initialize() {
  [alice, feeTo] = await ethers.getSigners();
  aliceEncoded = ethers.utils.defaultAbiCoder.encode(
    ["address"],
    [alice.address]
  );

  const ERC20 = await ethers.getContractFactory("ERC20Mock");
  const Bento = await ethers.getContractFactory("BentoBoxV1");
  const Deployer = await ethers.getContractFactory("MasterDeployer");
  const PoolFactory = await ethers.getContractFactory(
    "FranchisedConstantProductPoolFactory"
  );
  const TridentRouter = await ethers.getContractFactory("TridentRouter");
  const Pool = await ethers.getContractFactory("FranchisedConstantProductPool");
  const WhiteListManager = await ethers.getContractFactory("WhiteListManager");
  const whiteListManager = await WhiteListManager.deploy();

  weth = await ERC20.deploy("WETH", "WETH", getBigNumber("10000000"));
  usdc = await ERC20.deploy("USDC", "USDC", getBigNumber("10000000"));

  bento = await Bento.deploy(weth.address);

  masterDeployer = await Deployer.deploy(17, feeTo.address, bento.address);
  await masterDeployer.deployed();

  tridentPoolFactory = await PoolFactory.deploy(masterDeployer.address);
  await tridentPoolFactory.deployed();
  router = await TridentRouter.deploy(
    bento.address,
    masterDeployer.address,
    weth.address
  );
  await router.deployed();

  // Whitelist pool factory in master deployer
  await masterDeployer.addToWhitelist(tridentPoolFactory.address);

  // Whitelist Router on BentoBox
  await bento.whitelistMasterContract(router.address, true);
  // Approve BentoBox token deposits
  await weth.approve(bento.address, getBigNumber("10000000"));
  await usdc.approve(bento.address, getBigNumber("10000000"));

  // Make BentoBox token deposits
  await bento.deposit(
    weth.address,
    alice.address,
    alice.address,
    getBigNumber("1000000"),
    0
  );
  await bento.deposit(
    usdc.address,
    alice.address,
    alice.address,
    getBigNumber("1000000"),
    0
  );

  // Approve Router to spend 'alice' BentoBox tokens
  await bento.setMasterContractApproval(
    alice.address,
    router.address,
    true,
    "0",
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  );

  // Pool deploy data
  let addresses = [weth.address, usdc.address].sort();
  const deployData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "uint256", "bool", "address", "address", "bool"],
    [
      addresses[0],
      addresses[1],
      30,
      false,
      whiteListManager.address,
      alice.address,
      false,
    ]
  );

  whiteListManager.whitelistAccount(alice.address, true);

  pool = await Pool.attach(
    (
      await (
        await masterDeployer.deployPool(tridentPoolFactory.address, deployData)
      ).wait()
    ).events[0].args[1]
  );
}

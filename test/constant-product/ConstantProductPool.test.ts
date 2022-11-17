import { expect } from "chai";
import { BigNumber } from "ethers";
import { deployments, ethers, getNamedAccounts } from "hardhat";

import {
  BentoBoxV1,
  ConstantProductPoolFactory,
  ConstantProductPool__factory,
  ConstantProductPoolFactory__factory,
  ERC20Mock,
  ERC20Mock__factory,
  FlashSwapMock,
  FlashSwapMock__factory,
  MasterDeployer,
} from "../../types";
import { initializedConstantProductPool, uninitializedConstantProductPool } from "../fixtures";

describe("Constant Product Pool", () => {
  before(async () => {
    console.log("Deploying ConstantProductPoolFactory fixture");
    await deployments.fixture(["ConstantProductPoolFactory"]);
    console.log("Deployed ConstantProductPoolFactory fixture");
  });

  beforeEach(async () => {
    //
  });

  describe("#instantiation", () => {
    it("reverts if token0 is zero", async () => {
      const cppFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", 30, false]
      );
      await expect(cppFactory.deployPool(deployData)).to.be.revertedWith("ZeroAddress()");
    });

    it("deploys if token1 is zero", async () => {
      const cppFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000", 30, false]
      );
      await expect(cppFactory.deployPool(deployData)).to.be.revertedWith("ZeroAddress()");
    });

    it("reverts if token0 and token1 are identical", async () => {
      const cppFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000001", 30, false]
      );
      await expect(cppFactory.deployPool(deployData)).to.be.revertedWith("IdenticalAddress()");
    });
    it("reverts if swap fee more than the max fee", async () => {
      const cppFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 10001, false]
      );
      await expect(cppFactory.deployPool(deployData)).to.be.revertedWith("InvalidSwapFee()");
    });
  });

  describe("#mint", function () {
    it("reverts if total supply is 0 and one of the token amounts are 0 - token 0", async () => {
      const pool = await uninitializedConstantProductPool();

      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      const newLocal = "0x0000000000000000000000000000000000000003";

      await token0.transfer(bentoBox.address, 1000);

      await bentoBox.deposit(token0.address, bentoBox.address, pool.address, 1000, 0);

      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [newLocal]);
      await expect(pool.mint(mintData)).to.be.revertedWith("InvalidAmounts()");
    });

    it("reverts if total supply is 0 and one of the token amounts are 0 - token 1", async () => {
      const pool = await uninitializedConstantProductPool();

      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      const newLocal = "0x0000000000000000000000000000000000000003";

      await token1.transfer(bentoBox.address, 1000);

      await bentoBox.deposit(token1.address, bentoBox.address, pool.address, 1000, 0);

      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [newLocal]);
      await expect(pool.mint(mintData)).to.be.revertedWith("InvalidAmounts()");
    });

    it("reverts if insufficient liquidity minted", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      await token0.transfer(pool.address, 1);
      await token1.transfer(pool.address, 1);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await expect(pool.mint(mintData)).to.be.revertedWith("InsufficientLiquidityMinted()");
    });
  });

  describe("#burn", function () {
    //
  });

  describe("#burnSingle", function () {
    //
  });

  describe("#swap", function () {
    it("reverts on uninitialized", async () => {
      const pool = await uninitializedConstantProductPool();
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [await pool.token0(), "0x0000000000000000000000000000000000000000", false]
      );
      await expect(pool.swap(data)).to.be.revertedWith("PoolUninitialized()");
    });
    it("succeeds in swapping token 0", async () => {
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      const [r0, r1] = await pool.getNativeReserves();
      const swapData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, (await ethers.getSigners())[0].address, true]
      );
      const amountIn = 1000000;
      await token0.transfer(bento.address, amountIn);
      await bento.deposit(token0.address, bento.address, pool.address, amountIn, 0);
      await pool.swap(swapData);

      const [r0_, r1_] = await pool.getNativeReserves();
      expect(r0.add(amountIn).toString()).to.be.eq(r0_.toString());
      expect(r1_.lt(r1)).to.be.true;
    });
    it("succeeds in swapping tokens back and forth", async () => {
      // swap gas costs:  min  |  max  |  avg
      //                 54967 · 72882 · 59455
      const me = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      const [r0, r1] = await pool.getReserves();
      const amount = BigNumber.from((1e18).toString());
      await token0.transfer(bento.address, amount.mul(2));
      await token1.transfer(bento.address, amount);
      await bento.deposit(token0.address, bento.address, pool.address, amount, 0);
      await bento.deposit(token0.address, bento.address, me, amount, 0);
      await bento.deposit(token1.address, bento.address, me, amount, 0);
      const swapData0in = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, me, false]
      );
      const swapData1in = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token1.address, me, false]
      );
      await pool.swap(swapData0in);
      await bento.transfer(token1.address, me, pool.address, amount.div(2));
      await pool.swap(swapData1in);
      await bento.transfer(token0.address, me, pool.address, amount.div(2));
      await pool.swap(swapData0in);
      const [r0_, r1_] = await pool.getReserves();
      expect(r0_.gt(r0)).to.be.true;
      expect(r1_.lt(r1)).to.be.true;
    });
  });

  describe("#flashSwap", function () {
    it("reverts on uninitialized", async () => {
      const pool = await uninitializedConstantProductPool();
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [await pool.token0(), "0x0000000000000000000000000000000000000000", false, 0, "0x"]
      );
      await expect(pool.flashSwap(data)).to.be.revertedWith("PoolUninitialized()");
    });

    it("reverts on invalid input token", async () => {
      const pool = await initializedConstantProductPool();
      const ERC20 = await ethers.getContractFactory<ERC20Mock__factory>("ERC20Mock");
      const token2 = await ERC20.deploy("Token 2", "TOKEN2", ethers.constants.MaxUint256);
      await token2.deployed();

      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token2.address, "0x0000000000000000000000000000000000000000", false, 0, "0x"]
      );

      await expect(pool.flashSwap(data)).to.be.revertedWith("InvalidInputToken()");
    });

    it("reverts on insuffiecient amount in token 0", async () => {
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [false, "0x0000000000000000000000000000000000000000", false]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token0.address, flashSwapMock.address, false, 1, flashSwapData]
      );

      await expect(flashSwapMock.testFlashSwap(pool.address, data)).to.be.revertedWith("InsufficientAmountIn()");
    });

    it("reverts on insuffiecient amount in token 1", async () => {
      const pool = await initializedConstantProductPool();
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [false, "0x0000000000000000000000000000000000000000", false]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token1.address, flashSwapMock.address, false, 1, flashSwapData]
      );

      await expect(flashSwapMock.testFlashSwap(pool.address, data)).to.be.revertedWith("InsufficientAmountIn()");
    });

    it("succeeds in flash swapping token 0 native", async () => {
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      await token0.transfer(flashSwapMock.address, 100);

      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [true, token0.address, false]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token0.address, flashSwapMock.address, true, 100, flashSwapData]
      );
      await flashSwapMock.testFlashSwap(pool.address, data);
      expect(await token1.balanceOf(flashSwapMock.address)).to.be.eq(99);
    });

    it("succeeds in flash swapping token 0 bento", async () => {
      const pool = await initializedConstantProductPool();
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      await token0.transfer(bento.address, 100);
      await bento.deposit(token0.address, bento.address, flashSwapMock.address, 100, 0);

      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [true, token0.address, true]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token0.address, flashSwapMock.address, false, 100, flashSwapData]
      );
      await flashSwapMock.testFlashSwap(pool.address, data);
      expect(await bento.balanceOf(token1.address, flashSwapMock.address)).to.be.eq(99);
    });

    it("succeeds in flash swapping token 1 native", async () => {
      const pool = await initializedConstantProductPool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      await token1.transfer(flashSwapMock.address, 100);

      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [true, token1.address, false]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token1.address, flashSwapMock.address, true, 100, flashSwapData]
      );

      await flashSwapMock.testFlashSwap(pool.address, data);
      expect(await token0.balanceOf(flashSwapMock.address)).to.be.eq(99);
    });

    it("succeeds in flash swapping token 1 bento", async () => {
      const pool = await initializedConstantProductPool();
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const FlashSwapMock = await ethers.getContractFactory<FlashSwapMock__factory>("FlashSwapMock");
      const flashSwapMock = await FlashSwapMock.deploy(bento.address);
      await flashSwapMock.deployed();
      await token1.transfer(bento.address, 100);
      await bento.deposit(token1.address, bento.address, flashSwapMock.address, 100, 0);

      const flashSwapData = ethers.utils.defaultAbiCoder.encode(
        ["bool", "address", "bool"],
        [true, token1.address, true]
      );
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool", "uint256", "bytes"],
        [token1.address, flashSwapMock.address, false, 100, flashSwapData]
      );
      await flashSwapMock.testFlashSwap(pool.address, data);
      expect(await bento.balanceOf(token0.address, flashSwapMock.address)).to.be.eq(99);
    });
  });

  describe("#poolIdentifier", function () {
    //
  });

  describe("#getAssets", function () {
    it("returns the assets the pool was deployed with, and in the correct order", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const cppFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000002", "0x0000000000000000000000000000000000000001", 30, false]
      );
      await masterDeployer.deployPool(cppFactory.address, deployData);
      const addy = await cppFactory.calculatePoolAddress(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        30,
        false
      );
      const constantProductPool = ConstantProductPool.attach(addy);

      const assets = await constantProductPool.getAssets();

      await expect(assets[0], "0x0000000000000000000000000000000000000001");
      await expect(assets[1], "0x0000000000000000000000000000000000000002");
    });
  });

  describe("#updateBarParameters", () => {
    it("mutates bar fee if changed on master deployer", async () => {
      const pool = await initializedConstantProductPool();

      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");

      const { barFeeTo, bob } = await getNamedAccounts();

      expect(await pool.barFee()).equal(1667);

      expect(await pool.barFeeTo()).equal(barFeeTo);

      await masterDeployer.setBarFee(10).then((tx) => tx.wait());
      await masterDeployer.setBarFeeTo(bob).then((tx) => tx.wait());

      expect(await masterDeployer.barFee()).equal(10);
      expect(await masterDeployer.barFeeTo()).equal(bob);

      expect(await pool.barFee()).equal(1667);
      expect(await pool.barFeeTo()).equal(barFeeTo);

      await pool.updateBarParameters().then((tx) => tx.wait());

      expect(await pool.barFee()).equal(10);
      expect(await pool.barFeeTo()).equal(bob);

      // reset

      await masterDeployer.setBarFee(1667).then((tx) => tx.wait());
      await masterDeployer.setBarFeeTo(barFeeTo).then((tx) => tx.wait());

      expect(await masterDeployer.barFee()).equal(1667);
      expect(await masterDeployer.barFeeTo()).equal(barFeeTo);

      await pool.updateBarParameters().then((tx) => tx.wait());

      expect(await pool.barFee()).equal(1667);
      expect(await pool.barFeeTo()).equal(barFeeTo);
    });
  });

  describe("#getAmountOut", function () {
    it("returns 1000000000 given input of token0 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      const pool = await initializedConstantProductPool();
      const reserves = await pool.getReserves();
      expect(
        await pool.getAmountOut(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token0(), "1000000000"])
        )
      ).to.equal("999999999"); // 999999999
    });
    it("returns 999999999 given input of token1 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      const pool = await initializedConstantProductPool();
      const reserves = await pool.getReserves();
      expect(
        await pool.getAmountOut(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token1(), "1000000000"])
        )
      ).to.equal("999999999"); // 999999999
    });
    it("reverts if tokenIn is not equal to token0 and token1", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 30, false]
      );
      const cppFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");
      await masterDeployer.deployPool(cppFactory.address, deployData);
      const addy = await cppFactory.calculatePoolAddress(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        30,
        false
      );
      const constantProductPool = ConstantProductPool.attach(addy);

      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256"],
        ["0x0000000000000000000000000000000000000003", 0]
      );
      await expect(constantProductPool.getAmountOut(data)).to.be.revertedWith("InvalidInputToken()");
    });
  });

  describe("#getAmountIn", function () {
    it("returns 1000000002 given output of token0 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      const pool = await initializedConstantProductPool();
      expect(
        await pool.getAmountIn(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token0(), "1000000000"])
        )
      ).to.equal("1000000002"); // 1000000002
    });

    it("returns 1000000000 given output of token1 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      const pool = await initializedConstantProductPool();
      expect(
        await pool.getAmountIn(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token1(), "1000000000"])
        )
      ).to.equal("1000000002"); // 1000000002
    });
    it("reverts if tokenOut is not equal to token 1 and token0", async () => {
      const ConstantProductPool = await ethers.getContractFactory<ConstantProductPool__factory>("ConstantProductPool");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256", "bool"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 30, false]
      );
      const cppFactory = await ethers.getContract<ConstantProductPoolFactory>("ConstantProductPoolFactory");
      await masterDeployer.deployPool(cppFactory.address, deployData);
      const addy = await cppFactory.calculatePoolAddress(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        30,
        false
      );
      const constantProductPool = ConstantProductPool.attach(addy);
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256"],
        ["0x0000000000000000000000000000000000000003", 0]
      );
      await expect(constantProductPool.getAmountIn(data)).to.be.revertedWith("InvalidOutputToken()");
    });
  });

  describe("#getNativeReserves", function () {
    it("returns expected values for initilisedConstantProductPool", async () => {
      const pool = await initializedConstantProductPool();
      const [_nativeReserve0, _nativeReserve1, _blockTimestampLast] = await pool.getNativeReserves();
      expect(_nativeReserve0).equal("1000000000000000000");
      expect(_nativeReserve1).equal("1000000000000000000");
      expect(_blockTimestampLast).equal(0);
    });
  });
});

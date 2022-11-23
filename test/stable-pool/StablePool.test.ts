import { expect } from "chai";
import { BigNumber, utils } from "ethers";
import { deployments, ethers, getNamedAccounts } from "hardhat";

import {
  BentoBoxV1,
  StablePoolFactory,
  StablePool__factory,
  ERC20Mock,
  ERC20Mock__factory,
  MasterDeployer,
} from "../../types";
import { initializedStablePool, uninitializedStablePool, vanillaInitializedStablePool } from "../fixtures";

describe("Stable Pool", () => {
  before(async () => {
    console.log("Deploy StablePoolFactory fixture");
    await deployments.fixture(["StablePoolFactory"]);
    console.log("Deployed StablePoolFactory fixture");
  });

  beforeEach(async () => {
    //
  });

  describe("#instantiation", () => {
    it("reverts if token0 is zero", async () => {
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        ["0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000001", 30]
      );
      await expect(stableFactory.deployPool(deployData)).to.be.revertedWith("ZeroAddress()");
    });

    it("reverts if token1 is zero", async () => {
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000", 30]
      );
      await expect(stableFactory.deployPool(deployData)).to.be.revertedWith("ZeroAddress()");
    });

    it("reverts if token0 and token1 are identical", async () => {
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000001", 30]
      );
      await expect(stableFactory.deployPool(deployData)).to.be.revertedWith("IdenticalAddress()");
    });

    it("reverts if swap fee more than the max fee", async () => {
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002", 10001]
      );
      await expect(stableFactory.deployPool(deployData)).to.be.revertedWith("InvalidSwapFee()");
    });
  });

  describe("#mint", function () {
    it("reverts if total supply is 0 and one of the token amounts are 0 - token 0", async () => {
      const pool = await uninitializedStablePool();

      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      const newLocal = "0x0000000000000000000000000000000000000003";

      await token0.transfer(bentoBox.address, 1000);

      await bentoBox.deposit(token0.address, bentoBox.address, pool.address, 1000, 0);

      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [newLocal]);
      await expect(pool.mint(mintData)).to.be.revertedWith("InvalidAmounts()");
    });

    it("reverts if total supply is 0 and one of the token amounts are 0 - token 1", async () => {
      const pool = await uninitializedStablePool();

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
      const pool = await vanillaInitializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      await token0.transfer(pool.address, 1);
      await token1.transfer(pool.address, 1);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await expect(pool.mint(mintData)).to.be.revertedWith("InsufficientLiquidityMinted()");
    });

    it("simple adds more liquidity", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseUnits("100000000000", "18"));
      await token1.transfer(bento.address, ethers.utils.parseUnits("100000000000", "18"));
      await bento.deposit(
        token0.address,
        bento.address,
        pool.address,
        ethers.utils.parseUnits("100000000000", "18"),
        0
      );
      await bento.deposit(
        token1.address,
        bento.address,
        pool.address,
        ethers.utils.parseUnits("100000000000", "18"),
        0
      );
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData);
      // const getAmountOutData = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [token0.address, ethers.utils.parseUnits("100", '18')]);
      // console.log(ethers.utils.formatUnits(await pool.getAmountOut(getAmountOutData), '18'));
    });

    it.skip("simple adds small quantity of liqudity", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseUnits("100000000000", "18"));
      await token1.transfer(bento.address, ethers.utils.parseUnits("100000000000", "18"));
      await bento.deposit(token0.address, bento.address, pool.address, BigNumber.from(1e14), 0);
      await bento.deposit(token1.address, bento.address, pool.address, BigNumber.from(1e14), 0);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData);
      // const getAmountOutData = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [token0.address, ethers.utils.parseUnits("100", '18')]);
      // console.log(ethers.utils.formatUnits(await pool.getAmountOut(getAmountOutData), '18'));
    });
  });

  describe("#burn", function () {
    it("burns all liquidity to token0 and token1 balances", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const bob = await ethers.getNamedSigner("bob");
      const pool = await vanillaInitializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));
      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      await pool.burn(burnData);

      expect(await token0.balanceOf(bob.address)).to.be.above(0);

      expect(await token1.balanceOf(bob.address)).to.be.above(0);
    });

    it("simple removes liquidity", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const bob = await ethers.getNamedSigner("bob");
      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await token1.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData);

      await token0.transfer(bento.address, ethers.utils.parseEther("100"));
      await token1.transfer(bento.address, ethers.utils.parseEther("100"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("100"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("100"), 0);
      const mintData2 = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData2);

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));

      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      const bal1 = await token0.balanceOf(bob.address);
      const bal2 = await token1.balanceOf(bob.address);

      await pool.burn(burnData);

      const bal3 = await token0.balanceOf(bob.address);
      const bal4 = await token1.balanceOf(bob.address);
      // console.log(bal3.sub(bal1).toString());
      // console.log(bal4.sub(bal2).toString());
    });
  });

  describe("#burnSingle", function () {
    it("removes liquidity all in token0", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const bob = await ethers.getNamedSigner("bob");
      const pool = await vanillaInitializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));
      const burnData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, bob.address, true]
      );
      await pool.burnSingle(burnData);

      expect(await token0.balanceOf(bob.address)).to.be.above(0);
    });

    it("removes liquidity all in token1", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const bob = await ethers.getNamedSigner("bob");
      const pool = await vanillaInitializedStablePool();
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));
      const burnData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token1.address, bob.address, true]
      );
      await pool.burnSingle(burnData);

      expect(await token1.balanceOf(bob.address)).to.be.above(0);
    });

    it("reverts if tokenOut is not equal to token0 or token1", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await vanillaInitializedStablePool();
      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));
      const burnData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        ["0x0000000000000000000000000000000000000003", deployer.address, true]
      );

      expect(pool.burnSingle(burnData)).to.be.revertedWith("InvalidOutputToken()");
    });
  });

  describe("#swap", function () {
    it("reverts if tokenOut is not equal to token0 or token1", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const pool = await vanillaInitializedStablePool();

      const swapData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        ["0x0000000000000000000000000000000000000003", deployer.address, true]
      );

      expect(pool.swap(swapData)).to.be.revertedWith("InvalidInputToken()");
    });

    it("swaps token0 to token1", async () => {
      const bob = await ethers.getNamedSigner("bob");
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      const pool = await vanillaInitializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      await token0.transfer(bento.address, "10000000");
      await bento.deposit(token0.address, bento.address, pool.address, "10000000", 0);
      const swapData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, bob.address, true]
      );
      await pool.swap(swapData);

      expect(await token1.balanceOf(bob.address)).to.be.above(0);
    });

    it("simple swap token1 to token0", async () => {
      const bob = await ethers.getNamedSigner("bob");
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      const pool = await vanillaInitializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      await token1.transfer(bento.address, "10000000");
      await bento.deposit(token1.address, bento.address, pool.address, "10000000", 0);
      const swapData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token1.address, bob.address, true]
      );
      await pool.swap(swapData);

      expect(await token0.balanceOf(bob.address)).to.be.above(0);
    });

    it("performs simple swap", async () => {
      const deployer = await ethers.getNamedSigner("deployer");
      const alice = await ethers.getNamedSigner("alice");
      const feeTo = await ethers.getNamedSigner("barFeeTo");
      const bob = await ethers.getNamedSigner("bob");

      const pool = await initializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());
      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      await token0.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await token1.transfer(bento.address, ethers.utils.parseEther("10000000000"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("10000000000"), 0);
      const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      // console.log((await pool.kLast()).toString());
      // console.log((await pool.balanceOf(feeTo.address)).toString());
      await pool.mint(mintData);
      // console.log((await pool.kLast()).toString());
      // console.log((await pool.balanceOf(feeTo.address)).toString());
      await token0.transfer(bento.address, ethers.utils.parseEther("1"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      const swapData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, alice.address, true]
      );
      await pool.swap(swapData);
      // console.log((await token1.balanceOf(alice.address)).toString());
      // console.log((await pool.kLast()).toString());
      // console.log((await pool.balanceOf(feeTo.address)).toString());

      await token0.transfer(bento.address, ethers.utils.parseEther("100"));
      await token1.transfer(bento.address, ethers.utils.parseEther("100"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("100"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("100"), 0);
      const mintData2 = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData2);
      // console.log((await pool.kLast()).toString());
      // console.log((await pool.balanceOf(feeTo.address)).toString());

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));

      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      const bal1 = await token0.balanceOf(bob.address);
      const bal2 = await token1.balanceOf(bob.address);

      await pool.burn(burnData);

      const bal3 = await token0.balanceOf(bob.address);
      const bal4 = await token1.balanceOf(bob.address);
      // console.log(bal3.sub(bal1).toString());
      // console.log(bal4.sub(bal2).toString());
    });
  });

  describe("#flashSwap", function () {
    it("reverts on call", async () => {
      // flashSwap not supported on StablePool
      const pool = await vanillaInitializedStablePool();
      await expect(pool.flashSwap("0x0000000000000000000000000000000000000001")).to.be.reverted;
    });
  });

  describe("#poolIdentifier", function () {
    it("returns correct identifier for Stable Pools", async () => {
      const pool = await vanillaInitializedStablePool();
      expect(await (await pool.poolIdentifier()).toString()).to.equal(utils.formatBytes32String("Trident:StablePool"));
    });
  });

  describe("#getAssets", function () {
    it("returns the assets the pool was deployed with, and in the correct order", async () => {
      const StablePool = await ethers.getContractFactory<StablePool__factory>("StablePool");
      const stableFactory = await ethers.getContract<StablePoolFactory>("StablePoolFactory");
      const masterDeployer = await ethers.getContract<MasterDeployer>("MasterDeployer");
      const ERC20 = await ethers.getContractFactory<ERC20Mock__factory>("ERC20Mock");
      let token0 = await ERC20.deploy("Token 0", "TOKEN0", ethers.constants.MaxUint256);
      let token1 = await ERC20.deploy("Token 1", "TOKEN1", ethers.constants.MaxUint256);
      const deployData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "uint256"],
        [token0.address, token1.address, 30]
      );
      await masterDeployer.deployPool(stableFactory.address, deployData);

      if (token0.address > token1.address) {
        const saveToken = token0;
        token0 = token1;
        token1 = saveToken;
      }

      const addy = await stableFactory.calculatePoolAddress(token0.address, token1.address, 30);
      const stablePool = StablePool.attach(addy);
      const assets = await stablePool.getAssets();

      await expect(assets[0], token0.address);
      await expect(assets[1], token1.address);
    });
  });

  describe("#skim", function () {
    it("skims extra 1000000000 token0 on pool", async () => {
      const pool = await vanillaInitializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      await token0.transfer(pool.address, 1000000000);
      expect(await token0.balanceOf(pool.address)).to.equal(1000000000);

      await pool.skim();
      expect(await token0.balanceOf(pool.address)).to.equal(0);
    });

    it("skims extra 1000000000 token1 on pool", async () => {
      const pool = await vanillaInitializedStablePool();
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      await token1.transfer(pool.address, 1000000000);
      expect(await token1.balanceOf(pool.address)).to.equal(1000000000);

      await pool.skim();
      expect(await token1.balanceOf(pool.address)).to.equal(0);
    });

    it("skims extra 1000000000 token1 & token0 on pool", async () => {
      const pool = await vanillaInitializedStablePool();
      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      await token0.transfer(pool.address, 1000000000);
      await token1.transfer(pool.address, 1000000000);
      expect(await token0.balanceOf(pool.address)).to.equal(1000000000);
      expect(await token1.balanceOf(pool.address)).to.equal(1000000000);

      await pool.skim();
      expect(await token0.balanceOf(pool.address)).to.equal(0);
      expect(await token1.balanceOf(pool.address)).to.equal(0);
    });
  });

  describe("#updateBarParameters", function () {
    it("mutates bar fee if changed on master deployer", async () => {
      const pool = await vanillaInitializedStablePool();

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
      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      const pool = await vanillaInitializedStablePool();
      const shareIn = await bentoBox.toShare(await pool.token0(), 1000000000, false);
      const shareOut = await pool.getAmountOut(
        ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token0(), shareIn])
      );
      expect(await bentoBox.toAmount(await pool.token1(), shareOut, false)).to.equal("999000000");
    });

    it("returns 1000000000 given input of token1 in 1e18:1e18 pool, with bar fee 0 & swap fee 0", async () => {
      //todo: need to rework the fixture for these
      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      const pool = await vanillaInitializedStablePool();
      const shareIn = await bentoBox.toShare(await pool.token1(), 1000000000, false);
      const shareOut = await pool.getAmountOut(
        ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token1(), shareIn])
      );
      expect(await bentoBox.toAmount(await pool.token0(), shareOut, false)).to.equal("999000000");
    });

    it("reverts if tokenIn is not equal to token0 and token1", async () => {
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256"],
        ["0x0000000000000000000000000000000000000003", 0]
      );
      const pool = await vanillaInitializedStablePool();
      expect(pool.getAmountOut(data)).to.be.revertedWith("InvalidInputToken()");
    });
  });

  describe("#getAmountIn", function () {
    it("reverts on call", async () => {
      // getAmountIn not supported on StablePool
      const pool = await vanillaInitializedStablePool();

      const data = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [await pool.token0(), "1000000000"]);
      await expect(pool.getAmountIn(data)).to.be.reverted;
    });
  });

  describe("#getReserves", function () {
    it("returns expected values for initiliazedStablePool", async () => {
      const pool = await vanillaInitializedStablePool();
      const [reserve0, reserve1] = await pool.getReserves();
      expect(reserve0).equal("1000000000000000000");
      expect(reserve1).equal("1000000000000000000");
    });
  });

  describe("#getNativeReserves", function () {
    it("returns expected values for initiliazedStablePool", async () => {
      const pool = await vanillaInitializedStablePool();
      const [reserve0, reserve1] = await pool.getNativeReserves();
      expect(reserve0).equal("1000000000000000000");
      expect(reserve1).equal("1000000000000000000");
    });
  });
});

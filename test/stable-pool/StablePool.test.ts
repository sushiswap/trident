import { expect, util } from "chai";
import { BigNumber } from "ethers";
import { deployments, ethers } from "hardhat";

import type {
  BentoBoxV1,
  StablePool__factory,
  ERC20Mock,
  ERC20Mock__factory,
  FlashSwapMock,
  FlashSwapMock__factory,
  MasterDeployer,
} from "../../types";
import { initializedStablePool, uninitializedStablePool } from "../fixtures";

describe("Stable Pool", () => {
  before(async () => {
    console.log("Deploy MasterDeployer fixture");
    await deployments.fixture(["MasterDeployer"]);
    console.log("Deployed MasterDeployer fixture");
  });

  beforeEach(async () => {
    //
  });

  describe("#mint", function () {
    it("adds more liqudity", async () => {
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

    it("adds small quantity of liqudity", async () => {
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

    it("removes liquidity", async () => {
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

      await token0.transfer(bento.address, ethers.utils.parseEther("1"));
      await token1.transfer(bento.address, ethers.utils.parseEther("1"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      const mintData2 = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData2);

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));

      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      const bal1 = await token0.balanceOf(bob.address);
      const bal2 = await token1.balanceOf(bob.address);

      await pool.burn(burnData);

      const bal3 = await token0.balanceOf(bob.address);
      const bal4 = await token1.balanceOf(bob.address);
      console.log(bal3.sub(bal1).toString());
      console.log(bal4.sub(bal2).toString());
    });

    it("swap", async () => {
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
      console.log((await pool.kLast()).toString());
      console.log((await pool.balanceOf(feeTo.address)).toString());
      await pool.mint(mintData);
      console.log((await pool.kLast()).toString());
      console.log((await pool.balanceOf(feeTo.address)).toString());
      await token0.transfer(bento.address, ethers.utils.parseEther("1"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      const swapData = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, alice.address, true]
      );
      await pool.swap(swapData);
      console.log((await token1.balanceOf(alice.address)).toString());
      console.log((await pool.kLast()).toString());
      console.log((await pool.balanceOf(feeTo.address)).toString());

      await token0.transfer(bento.address, ethers.utils.parseEther("1"));
      await token1.transfer(bento.address, ethers.utils.parseEther("1"));
      await bento.deposit(token0.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      await bento.deposit(token1.address, bento.address, pool.address, ethers.utils.parseEther("1"), 0);
      const mintData2 = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
      await pool.mint(mintData2);
      console.log((await pool.kLast()).toString());
      console.log((await pool.balanceOf(feeTo.address)).toString());

      await pool.transfer(pool.address, await pool.balanceOf(deployer.address));

      const burnData = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [bob.address, true]);
      const bal1 = await token0.balanceOf(bob.address);
      const bal2 = await token1.balanceOf(bob.address);

      await pool.burn(burnData);

      const bal3 = await token0.balanceOf(bob.address);
      const bal4 = await token1.balanceOf(bob.address);
      console.log(bal3.sub(bal1).toString());
      console.log(bal4.sub(bal2).toString());
    });
  });
});

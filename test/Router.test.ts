// @ts-nocheck

import { ethers } from "hardhat";
import { expect } from "chai";
import { prepare, deploy, getBigNumber } from "./utilities"
import { BigNumber } from 'ethers';
import { Multicall } from '../typechain/Multicall';

describe("Router", function () {
  let alice, feeTo, weth, sushi, bento, masterDeployer, mirinPoolFactory, router, pool, dai, daiSushiPool, daiWethPool;

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("ConstantProductPoolFactory");
    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    const Pool = await ethers.getContractFactory("ConstantProductPool");

    weth = await ERC20.deploy("WETH", "ETH", getBigNumber("10000000"));
    sushi = await ERC20.deploy("SUSHI", "SUSHI", getBigNumber("10000000"));
    dai = await ERC20.deploy("SUSHI", "SUSHI", getBigNumber("10000000"));
    bento = await Bento.deploy(weth.address);
    masterDeployer = await Deployer.deploy(17, feeTo.address, bento.address);
    mirinPoolFactory = await PoolFactory.deploy();
    router = await SwapRouter.deploy(weth.address, masterDeployer.address, bento.address);

    // Whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(mirinPoolFactory.address);

    // Whitelist Router on BentoBox
    await bento.whitelistMasterContract(router.address, true);
    // Approve BentoBox token deposits
    await sushi.approve(bento.address, BigNumber.from(10).pow(30));
    await weth.approve(bento.address, BigNumber.from(10).pow(30));
    await dai.approve(bento.address, BigNumber.from(10).pow(30));
    // Make BentoBox token deposits
    await bento.deposit(sushi.address, alice.address, alice.address, BigNumber.from(10).pow(22), 0);
    await bento.deposit(weth.address, alice.address, alice.address, BigNumber.from(10).pow(22), 0);
    await bento.deposit(dai.address, alice.address, alice.address, BigNumber.from(10).pow(22), 0);
    // Approve Router to spend 'alice' BentoBox tokens
    await bento.setMasterContractApproval(alice.address, router.address, true, "0", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000");
    // Pool deploy data
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint8"],
      [weth.address, sushi.address, 30]
    );
    pool = await Pool.attach(
      (await (await masterDeployer.deployPool(mirinPoolFactory.address, deployData)).wait()).events[0].args[0]
    );
    const deployData2 = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint8"],
      [dai.address, sushi.address, 30]
    );
    daiSushiPool = await Pool.attach(
      (await (await masterDeployer.deployPool(mirinPoolFactory.address, deployData2)).wait()).events[0].args[0]
    );
    const deployData3 = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint8"],
      [dai.address, weth.address, 30]
    );
    daiWethPool = await Pool.attach(
      (await (await masterDeployer.deployPool(mirinPoolFactory.address, deployData3)).wait()).events[0].args[0]
    );
  })

  describe("ConstantProductPool", function() {
    it("Pool should have correct tokens", async function() {
      expect(await pool.token0()).eq(weth.address);
      expect(await pool.token1()).eq(sushi.address);
    });

    it("Should add liquidity directly to the pool", async function() {
      await bento.transfer(sushi.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await bento.transfer(weth.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await pool.mint(alice.address);
      expect(await pool.totalSupply()).gt(1);
      await bento.transfer(sushi.address, alice.address, daiSushiPool.address, BigNumber.from(10).pow(20));
      await bento.transfer(dai.address, alice.address, daiSushiPool.address, BigNumber.from(10).pow(20));
      await daiSushiPool.mint(alice.address);
      expect(await daiSushiPool.totalSupply()).gt(1);
      await bento.transfer(weth.address, alice.address, daiWethPool.address, BigNumber.from(10).pow(20));
      await bento.transfer(dai.address, alice.address, daiWethPool.address, BigNumber.from(10).pow(20));
      await daiWethPool.mint(alice.address);
      expect(await daiWethPool.totalSupply()).gt(1);
    });

    it("Should add balanced liquidity", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let initialPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);
      let liquidityInput = [
        {"token" : weth.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : sushi.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());
      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let intermediatePoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolWethBalance).eq(initialPoolWethBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolSushiBalance).eq(initialPoolSushiBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).eq(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(intermediatePoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).eq(initialPoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      liquidityInput = [
        {"token" : weth.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(17), "amountMin" : 1},
        {"token" : sushi.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let finalPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolWethBalance).eq(intermediatePoolWethBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolSushiBalance).eq(intermediatePoolSushiBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
      expect(finalPoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(intermediatePoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
    });

    it("Should add one sided liquidity", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let initialPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);

      let liquidityInputOptimal = [{"token" : weth.address, "native" : false, "amount" : BigNumber.from(10).pow(18)}];
      await router.addLiquidityUnbalanced(liquidityInputOptimal, pool.address, alice.address, 2 * Date.now(), 1);

      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let intermediatePoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolWethBalance).gt(initialPoolWethBalance);
      expect(intermediatePoolSushiBalance).eq(initialPoolSushiBalance);
      expect(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).gt(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));

      liquidityInputOptimal = [{"token" : sushi.address, "native" : false, "amount" : BigNumber.from(10).pow(18)}];
      await router.addLiquidityUnbalanced(liquidityInputOptimal, pool.address, alice.address, 2 * Date.now(), 1);

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let finalPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolWethBalance).eq(intermediatePoolWethBalance);
      expect(finalPoolSushiBalance).gt(intermediatePoolSushiBalance);
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).lt(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
      expect(finalPoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).gt(intermediatePoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
    });

    it("Should swap some tokens", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOut = await pool.getAmountOut(weth.address, amountIn);
      expect(expectedAmountOut).gt(1);
      let params = {
        "tokenIn" : weth.address,
        "tokenOut" : sushi.address,
        "pool" : pool.address,
        "recipient" : alice.address,
        "unwrapBento": false,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };
      let oldAliceWethBalance = await bento.balanceOf(weth.address, alice.address);
      let oldAliceSushiBalance = await bento.balanceOf(sushi.address, alice.address);
      let oldPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let oldPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);
      await router.exactInputSingle(params);
      expect(await bento.balanceOf(weth.address, alice.address)).eq(oldAliceWethBalance.sub(amountIn));
      expect(await bento.balanceOf(sushi.address, alice.address)).eq(oldAliceSushiBalance.add(expectedAmountOut));
      expect(await bento.balanceOf(weth.address, pool.address)).eq(oldPoolWethBalance.add(amountIn));
      expect(await bento.balanceOf(sushi.address, pool.address)).eq(oldPoolSushiBalance.sub(expectedAmountOut));

      amountIn = expectedAmountOut;
      expectedAmountOut = await pool.getAmountOut(sushi.address, amountIn);
      expect(expectedAmountOut).lt(BigNumber.from(10).pow(18));
      params = {
        "tokenIn" : sushi.address,
        "tokenOut" : weth.address,
        "pool" : pool.address,
        "recipient" : alice.address,
        "unwrapBento": true,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : expectedAmountOut
      };

      await router.exactInputSingle(params);
      expect(await bento.balanceOf(weth.address, alice.address)).lt(oldAliceWethBalance);
      expect(await bento.balanceOf(sushi.address, alice.address)).eq(oldAliceSushiBalance);
      expect(await bento.balanceOf(weth.address, pool.address)).gt(oldPoolWethBalance);
      expect(await bento.balanceOf(sushi.address, pool.address)).eq(oldPoolSushiBalance);

      amountIn = expectedAmountOut;
      expectedAmountOut = await pool.getAmountOut(weth.address, amountIn);
      params = {
        "tokenIn" : weth.address,
        "tokenOut" : sushi.address,
        "pool" : pool.address,
        "recipient" : alice.address,
        "unwrapBento": false,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : expectedAmountOut,
        "context": "0x"
      };

      oldAliceWethBalance = await bento.balanceOf(weth.address, alice.address);
      oldAliceSushiBalance = await bento.balanceOf(sushi.address, alice.address);
      oldPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      oldPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);

      await router.exactInputSingleWithContext(params, { gasLimit : 1000000});

      expect(await bento.balanceOf(weth.address, alice.address)).lt(oldAliceWethBalance);
      expect(await bento.balanceOf(sushi.address, alice.address)).gt(oldAliceSushiBalance);
      expect(await bento.balanceOf(weth.address, pool.address)).gt(oldPoolWethBalance);
      expect(await bento.balanceOf(sushi.address, pool.address)).lt(oldPoolSushiBalance);
    });

    it("Should handle multi hop swaps", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOutSingleHop = await pool.getAmountOut(weth.address, amountIn);
      expect(expectedAmountOutSingleHop).gt(1);
      let params = {
        "path" : [
          {"tokenIn" : weth.address, "pool" : pool.address},
          {"tokenIn" : sushi.address, "pool" : daiSushiPool.address},
          {"tokenIn" : dai.address, "pool" : daiWethPool.address},
          {"tokenIn" : weth.address, "pool" : pool.address},
        ],
        "tokenOut" : sushi.address,
        "recipient" : alice.address,
        "unwrapBento": false,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };

      let oldAliceWethBalance = await bento.balanceOf(weth.address, alice.address);
      let oldAliceSushiBalance = await bento.balanceOf(sushi.address, alice.address);
      let oldPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let oldPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);
      await router.exactInput(params);
      expect(await bento.balanceOf(weth.address, alice.address)).eq(oldAliceWethBalance.sub(amountIn));
      expect(await bento.balanceOf(sushi.address, alice.address)).lt(oldAliceSushiBalance.add(expectedAmountOutSingleHop));
      expect(await bento.balanceOf(weth.address, pool.address)).gt(oldPoolWethBalance.add(amountIn));
      expect(await bento.balanceOf(sushi.address, pool.address)).gt(oldPoolSushiBalance.sub(BigNumber.from(2).mul(expectedAmountOutSingleHop)));
    });

    it("Should add balanced liquidity to unbalanced pool", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let initialPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);
      let liquidityInput = [
        {"token" : weth.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : sushi.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());
      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let intermediatePoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolWethBalance).eq(initialPoolWethBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolSushiBalance).gt(initialPoolSushiBalance);
      expect(intermediatePoolSushiBalance).lt(initialPoolSushiBalance.add(BigNumber.from(10).pow(18)));

      // Swap fee deducted
      expect(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).lte(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(intermediatePoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).lte(initialPoolSushiBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));

      liquidityInput = [
        {"token" : sushi.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : weth.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(17), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let finalPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolWethBalance).eq(intermediatePoolWethBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolSushiBalance).gt(intermediatePoolSushiBalance);
      expect(finalPoolSushiBalance).lt(intermediatePoolSushiBalance.add(BigNumber.from(10).pow(17)));

      // Using 18 decimal precision rather than 36 here to accommodate for 1wei rounding errors
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(18)).div(finalTotalSupply)).eq(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(18)).div(intermediateTotalSupply));
      expect(finalPoolSushiBalance.mul(BigNumber.from(10).pow(18)).div(finalTotalSupply)).eq(intermediatePoolSushiBalance.mul(BigNumber.from(10).pow(18)).div(intermediateTotalSupply));
    });

    it("Should swap some native tokens", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOut = await pool.getAmountOut(weth.address, amountIn);
      expect(expectedAmountOut).gt(1);
      let params = {
        "tokenIn" : weth.address,
        "tokenOut" : sushi.address,
        "pool" : pool.address,
        "recipient" : alice.address,
        "unwrapBento": true,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };

      let oldAliceWethBalance = await weth.balanceOf(alice.address);
      let oldAliceSushiBalance = await sushi.balanceOf(alice.address);
      let oldPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let oldPoolSushiBalance = await bento.balanceOf(sushi.address, pool.address);
      let oldAliceBentoWethBalance = await bento.balanceOf(weth.address, alice.address);
      let oldAliceBentoSushiBalance = await bento.balanceOf(sushi.address, alice.address);

      await router.exactInputSingleWithNativeToken(params);

      expect(await weth.balanceOf(alice.address)).eq(oldAliceWethBalance.sub(amountIn));
      expect(await sushi.balanceOf(alice.address)).eq(oldAliceSushiBalance.add(expectedAmountOut));
      expect(await bento.balanceOf(sushi.address, alice.address)).eq(oldAliceBentoSushiBalance);
      expect(await bento.balanceOf(weth.address, alice.address)).eq(oldAliceBentoWethBalance);
      expect(await bento.balanceOf(weth.address, pool.address)).eq(oldPoolWethBalance.add(amountIn));
      expect(await bento.balanceOf(sushi.address, pool.address)).eq(oldPoolSushiBalance.sub(expectedAmountOut));

      amountIn = expectedAmountOut;
      expectedAmountOut = await pool.getAmountOut(sushi.address, amountIn);
      expect(expectedAmountOut).lt(BigNumber.from(10).pow(18));
      params = {
        "tokenIn" : sushi.address,
        "tokenOut" : weth.address,
        "pool" : pool.address,
        "recipient" : alice.address,
        "unwrapBento": false,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : expectedAmountOut
      };

      oldAliceWethBalance = await weth.balanceOf(alice.address);
      oldAliceSushiBalance = await sushi.balanceOf(alice.address);
      oldAliceBentoWethBalance = await bento.balanceOf(weth.address, alice.address);
      oldAliceBentoSushiBalance = await bento.balanceOf(sushi.address, alice.address);

      await router.exactInputSingleWithNativeToken(params);
      expect(await weth.balanceOf(alice.address)).eq(oldAliceWethBalance);
      expect(await sushi.balanceOf(alice.address)).eq(oldAliceSushiBalance.sub(amountIn));
      expect(await bento.balanceOf(sushi.address, alice.address)).eq(oldAliceBentoSushiBalance);
      expect(await bento.balanceOf(weth.address, alice.address)).eq(oldAliceBentoWethBalance.add(expectedAmountOut));
    });
  });
})

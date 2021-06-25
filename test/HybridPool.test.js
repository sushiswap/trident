const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { prepare, deploy, getBigNumber } = require("./utilities");


describe("Router", function () {
  let alice, feeTo, usdt, usdc, bento, masterDeployer, mirinPoolFactory, router, pool;

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("HybridPoolFactory");
    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    const Pool = await ethers.getContractFactory("HybridPool");

    usdt = await ERC20.deploy("USDT", "USDT", getBigNumber("10000000"));
    usdc = await ERC20.deploy("USDC", "USDC", getBigNumber("10000000"));
    bento = await Bento.deploy(usdt.address);
    masterDeployer = await Deployer.deploy(17, feeTo.address, bento.address);
    mirinPoolFactory = await PoolFactory.deploy();
    router = await SwapRouter.deploy(usdt.address, masterDeployer.address, bento.address);

    // Whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(mirinPoolFactory.address);

    // Whitelist Router on BentoBox
    await bento.whitelistMasterContract(router.address, true);
    // Approve BentoBox token deposits
    await usdc.approve(bento.address, getBigNumber("10000000"));
    await usdt.approve(bento.address, getBigNumber("10000000"));
    // Make BentoBox token deposits
    await bento.deposit(usdc.address, alice.address, alice.address, getBigNumber("1000000"), 0);
    await bento.deposit(usdt.address, alice.address, alice.address, getBigNumber("1000000"), 0);
    // Approve Router to spend 'alice' BentoBox tokens
    await bento.setMasterContractApproval(alice.address, router.address, true, "0", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000");
    // Pool deploy data
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint8", "uint256"],
      [usdt.address, usdc.address, 30, 200000]
    );
    // Pool initialize data
    const initData = Pool.interface.encodeFunctionData("init");
    pool = await Pool.attach(
      (await (await masterDeployer.deployPool(mirinPoolFactory.address, deployData, initData)).wait()).events[1].args[0]
    );
  })

  describe("Pool", function() {
    it("Pool should have correct tokens", async function() {
      expect(await pool.token0()).eq(usdt.address);
      expect(await pool.token1()).eq(usdc.address);
    });

    it("Should add liquidity directly to the pool", async function() {
      await bento.transfer(usdc.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await bento.transfer(usdt.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await pool.mint(alice.address);
      expect(await pool.totalSupply()).gt(1);
    });

    it("Should add balanced liquidity", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let initialPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      let liquidityInput = [
        {"token" : usdt.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : usdc.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());
      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let intermediatePoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolUsdtBalance).eq(initialPoolUsdtBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolUsdcBalance).eq(initialPoolUsdcBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).eq(initialPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).eq(initialPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      liquidityInput = [
        {"token" : usdt.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(17), "amountMin" : 1},
        {"token" : usdc.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let finalPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolUsdtBalance).eq(intermediatePoolUsdtBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolUsdcBalance).eq(intermediatePoolUsdcBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(intermediatePoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
    });

    it("Should add one sided liquidity", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let initialPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      let liquidityInputOptimal = [{"token" : usdt.address, "native" : false, "amount" : BigNumber.from(10).pow(18)}];
      await router.addLiquidityUnbalanced(liquidityInputOptimal, pool.address, alice.address, 2 * Date.now(), 1);

      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let intermediatePoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolUsdtBalance).gt(initialPoolUsdtBalance);
      expect(intermediatePoolUsdcBalance).eq(initialPoolUsdcBalance);
      expect(intermediatePoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).gt(initialPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));

      liquidityInputOptimal = [{"token" : usdc.address, "native" : false, "amount" : BigNumber.from(10).pow(18)}];
      await router.addLiquidityUnbalanced(liquidityInputOptimal, pool.address, alice.address, 2 * Date.now(), 1);

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let finalPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolUsdtBalance).eq(intermediatePoolUsdtBalance);
      expect(finalPoolUsdcBalance).gt(intermediatePoolUsdcBalance);
      expect(finalPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).lt(intermediatePoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).gt(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
    });

    it("Should swap some tokens", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOut = await pool.getAmountOut(usdt.address, amountIn);
      expect(expectedAmountOut).gt(1);
      let params = {
        "tokenIn" : usdt.address,
        "tokenOut" : usdc.address,
        "pool" : pool.address,
        "context" : "0x",
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };
      let oldAliceUsdtBalance = await bento.balanceOf(usdt.address, alice.address);
      let oldAliceUsdcBalance = await bento.balanceOf(usdc.address, alice.address);
      let oldPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let oldPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      await router.exactInputSingle(params);
      expect(await bento.balanceOf(usdt.address, alice.address)).eq(oldAliceUsdtBalance.sub(amountIn));
      expect(await bento.balanceOf(usdc.address, alice.address)).eq(oldAliceUsdcBalance.add(expectedAmountOut));
      expect(await bento.balanceOf(usdt.address, pool.address)).eq(oldPoolUsdtBalance.add(amountIn));
      expect(await bento.balanceOf(usdc.address, pool.address)).eq(oldPoolUsdcBalance.sub(expectedAmountOut));

      amountIn = expectedAmountOut;
      expectedAmountOut = await pool.getAmountOut(usdc.address, amountIn);
      expect(expectedAmountOut).lt(BigNumber.from(10).pow(18));
      params = {
        "tokenIn" : usdc.address,
        "tokenOut" : usdt.address,
        "pool" : pool.address,
        "context" : "0x",
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : expectedAmountOut
      };

      await router.exactInputSingle(params);
      expect(await bento.balanceOf(usdt.address, alice.address)).lt(oldAliceUsdtBalance);
      expect(await bento.balanceOf(usdc.address, alice.address)).eq(oldAliceUsdcBalance);
      expect(await bento.balanceOf(usdt.address, pool.address)).gt(oldPoolUsdtBalance);
      expect(await bento.balanceOf(usdc.address, pool.address)).eq(oldPoolUsdcBalance);
    });

    it("Should handle multi hop swaps", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOutSingleHop = await pool.getAmountOut(usdt.address, amountIn);
      expect(expectedAmountOutSingleHop).gt(1);
      let params = {
        "path" : [
          {"tokenIn" : usdt.address, "pool" : pool.address, "context" : "0x"},
          {"tokenIn" : usdc.address, "pool" : pool.address, "context" : "0x"},
          {"tokenIn" : usdt.address, "pool" : pool.address, "context" : "0x"},
        ],
        "tokenOut" : usdc.address,
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };

      let oldAliceUsdtBalance = await bento.balanceOf(usdt.address, alice.address);
      let oldAliceUsdcBalance = await bento.balanceOf(usdc.address, alice.address);
      let oldPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let oldPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      await router.exactInput(params);
      expect(await bento.balanceOf(usdt.address, alice.address)).eq(oldAliceUsdtBalance.sub(amountIn));
      expect(await bento.balanceOf(usdc.address, alice.address)).lt(oldAliceUsdcBalance.add(expectedAmountOutSingleHop));
      expect(await bento.balanceOf(usdt.address, pool.address)).eq(oldPoolUsdtBalance.add(amountIn));
      expect(await bento.balanceOf(usdc.address, pool.address)).gt(oldPoolUsdcBalance.sub(expectedAmountOutSingleHop));
    });

    it("Should add balanced liquidity to unbalanced pool", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let initialPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      let liquidityInput = [
        {"token" : usdt.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : usdc.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());
      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let intermediatePoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolUsdtBalance).eq(initialPoolUsdtBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolUsdcBalance).gt(initialPoolUsdcBalance);
      expect(intermediatePoolUsdcBalance).lt(initialPoolUsdcBalance.add(BigNumber.from(10).pow(18)));

      // Swap fee deducted
      expect(intermediatePoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).lte(initialPoolUsdtBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).lte(initialPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));

      liquidityInput = [
        {"token" : usdc.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : usdt.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(17), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let finalPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolUsdtBalance).eq(intermediatePoolUsdtBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolUsdcBalance).gt(intermediatePoolUsdcBalance);
      expect(finalPoolUsdcBalance).lt(intermediatePoolUsdcBalance.add(BigNumber.from(10).pow(17)));

      // Using 18 decimal precision rather than 36 here to accommodate for 1wei rounding errors
      expect(finalPoolUsdtBalance.mul(BigNumber.from(10).pow(18)).div(finalTotalSupply)).eq(intermediatePoolUsdtBalance.mul(BigNumber.from(10).pow(18)).div(intermediateTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(18)).div(finalTotalSupply)).eq(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(18)).div(intermediateTotalSupply));
    });

    it("Should swap some native tokens", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOut = await pool.getAmountOut(usdt.address, amountIn);
      expect(expectedAmountOut).gt(1);
      let params = {
        "tokenIn" : usdt.address,
        "tokenOut" : usdc.address,
        "pool" : pool.address,
        "context" : "0x",
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };

      let oldAliceUsdtBalance = await usdt.balanceOf(alice.address);
      let oldAliceUsdcBalance = await bento.balanceOf(usdc.address, alice.address);
      let oldPoolUsdtBalance = await bento.balanceOf(usdt.address, pool.address);
      let oldPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      let oldAliceBentoUsdtBalance = await bento.balanceOf(usdt.address, alice.address);

      //multicall
      await router.multicall([
        router.interface.encodeFunctionData("depositToBentoBox", [usdt.address, amountIn, pool.address]),
        router.interface.encodeFunctionData("exactInputSingleWithPreFunding", [params])
      ]);

      expect(await usdt.balanceOf(alice.address)).eq(oldAliceUsdtBalance.sub(amountIn));
      expect(await bento.balanceOf(usdc.address, alice.address)).eq(oldAliceUsdcBalance.add(expectedAmountOut));
      expect(await bento.balanceOf(usdt.address, pool.address)).eq(oldPoolUsdtBalance.add(amountIn));
      expect(await bento.balanceOf(usdc.address, pool.address)).eq(oldPoolUsdcBalance.sub(expectedAmountOut));
      expect(await bento.balanceOf(usdt.address, alice.address)).eq(oldAliceBentoUsdtBalance);

      amountIn = expectedAmountOut;
      expectedAmountOut = await pool.getAmountOut(usdc.address, amountIn);
      expect(expectedAmountOut).lt(BigNumber.from(10).pow(18));
      params = {
        "tokenIn" : usdc.address,
        "tokenOut" : usdt.address,
        "pool" : pool.address,
        "context" : "0x",
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : expectedAmountOut
      };

      await router.multicall([
        router.interface.encodeFunctionData("depositToBentoBox", [usdc.address, amountIn, pool.address]),
        router.interface.encodeFunctionData("exactInputSingleWithPreFunding", [params])
      ]);
      expect(await bento.balanceOf(usdt.address, pool.address)).gt(oldPoolUsdtBalance);
      expect(await bento.balanceOf(usdc.address, pool.address)).eq(oldPoolUsdcBalance);
    });
  });
})

const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { prepare, deploy, getBigNumber } = require("./utilities");

describe("Router", function () {
  let alice, feeTo, weth, usdc, bento, masterDeployer, tridentPoolFactory, router, pool;

  before(async function () {
    [alice, feeTo] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Bento = await ethers.getContractFactory("BentoBoxV1");
    const Deployer = await ethers.getContractFactory("MasterDeployer");
    const PoolFactory = await ethers.getContractFactory("HybridPoolFactory");
    const SwapRouter = await ethers.getContractFactory("TridentRouter");
    const Pool = await ethers.getContractFactory("HybridPool");

    weth = await ERC20.deploy("WETH", "WETH", getBigNumber("10000000"));
    usdc = await ERC20.deploy("USDC", "USDC", getBigNumber("10000000"));
    bento = await Bento.deploy(weth.address);
    masterDeployer = await Deployer.deploy(17, feeTo.address, bento.address);
    tridentPoolFactory = await PoolFactory.deploy(masterDeployer.address);
    router = await SwapRouter.deploy(bento.address, weth.address);

    // Whitelist pool factory in master deployer
    await masterDeployer.addToWhitelist(tridentPoolFactory.address);

    // Whitelist Router on BentoBox
    await bento.whitelistMasterContract(router.address, true);
    // Approve BentoBox token deposits
    await weth.approve(bento.address, getBigNumber("10000000"));
    await usdc.approve(bento.address, getBigNumber("10000000"));
    // Make BentoBox token deposits
    await bento.deposit(weth.address, alice.address, alice.address, getBigNumber("1000000"), 0);
    await bento.deposit(usdc.address, alice.address, alice.address, getBigNumber("1000000"), 0);
    // Approve Router to spend 'alice' BentoBox tokens
    await bento.setMasterContractApproval(alice.address, router.address, true, "0", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000");
    // Pool deploy data
    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint8", "uint256"],
      [weth.address, usdc.address, 30, 200000]
    );
    pool = await Pool.attach(
      (await (await masterDeployer.deployPool(tridentPoolFactory.address, deployData)).wait()).events[0].args[0]
    );
  })

  describe("Pool", function() {
    it("Pool should have correct tokens", async function() {
      expect(await pool.token0()).eq(weth.address);
      expect(await pool.token1()).eq(usdc.address);
    });

    it("Should add liquidity directly to the pool", async function() {
      await bento.transfer(weth.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await bento.transfer(usdc.address, alice.address, pool.address, BigNumber.from(10).pow(19));
      await pool.mint(alice.address);
      expect(await pool.totalSupply()).gt(1);
    });

    it("Should add balanced liquidity", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let initialPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      let liquidityInput = [
        {"token" : weth.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : usdc.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());
      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let intermediatePoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolWethBalance).eq(initialPoolWethBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolUsdcBalance).eq(initialPoolUsdcBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).eq(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).eq(initialPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      liquidityInput = [
        {"token" : weth.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(17), "amountMin" : 1},
        {"token" : usdc.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let finalPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolWethBalance).eq(intermediatePoolWethBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolUsdcBalance).eq(intermediatePoolUsdcBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
    });

    it("Should add one sided liquidity", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let initialPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      let liquidityInputOptimal = [{"token" : weth.address, "native" : false, "amount" : BigNumber.from(10).pow(18)}];
      await router.addLiquidityUnbalanced(liquidityInputOptimal, pool.address, alice.address, 2 * Date.now(), 1);

      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let intermediatePoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolWethBalance).gt(initialPoolWethBalance);
      expect(intermediatePoolUsdcBalance).eq(initialPoolUsdcBalance);
      expect(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).gt(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));

      liquidityInputOptimal = [{"token" : usdc.address, "native" : false, "amount" : BigNumber.from(10).pow(18)}];
      await router.addLiquidityUnbalanced(liquidityInputOptimal, pool.address, alice.address, 2 * Date.now(), 1);

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let finalPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolWethBalance).eq(intermediatePoolWethBalance);
      expect(finalPoolUsdcBalance).gt(intermediatePoolUsdcBalance);
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).lt(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).eq(initialPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(finalTotalSupply)).gt(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply));
    });

    it("Should swap some tokens", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOut = await pool.getAmountOut(weth.address, amountIn);
      expect(expectedAmountOut).gt(1);
      let params = {
        "tokenIn" : weth.address,
        "tokenOut" : usdc.address,
        "pool" : pool.address,
        "context" : "0x",
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };
      let oldAliceWethBalance = await bento.balanceOf(weth.address, alice.address);
      let oldAliceUsdcBalance = await bento.balanceOf(usdc.address, alice.address);
      let oldPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let oldPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      await router.exactInputSingle(params);
      expect(await bento.balanceOf(weth.address, alice.address)).eq(oldAliceWethBalance.sub(amountIn));
      expect(await bento.balanceOf(usdc.address, alice.address)).eq(oldAliceUsdcBalance.add(expectedAmountOut));
      expect(await bento.balanceOf(weth.address, pool.address)).eq(oldPoolWethBalance.add(amountIn));
      expect(await bento.balanceOf(usdc.address, pool.address)).eq(oldPoolUsdcBalance.sub(expectedAmountOut));

      amountIn = expectedAmountOut;
      expectedAmountOut = await pool.getAmountOut(usdc.address, amountIn);
      expect(expectedAmountOut).lt(BigNumber.from(10).pow(18));
      params = {
        "tokenIn" : usdc.address,
        "tokenOut" : weth.address,
        "pool" : pool.address,
        "context" : "0x",
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : expectedAmountOut
      };

      await router.exactInputSingle(params);
      expect(await bento.balanceOf(weth.address, alice.address)).lt(oldAliceWethBalance);
      expect(await bento.balanceOf(usdc.address, alice.address)).eq(oldAliceUsdcBalance);
      expect(await bento.balanceOf(weth.address, pool.address)).gt(oldPoolWethBalance);
      expect(await bento.balanceOf(usdc.address, pool.address)).eq(oldPoolUsdcBalance);
    });

    it("Should handle multi hop swaps", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOutSingleHop = await pool.getAmountOut(weth.address, amountIn);
      expect(expectedAmountOutSingleHop).gt(1);
      let params = {
        "path" : [
          {"tokenIn" : weth.address, "pool" : pool.address, "context" : "0x"},
          {"tokenIn" : usdc.address, "pool" : pool.address, "context" : "0x"},
          {"tokenIn" : weth.address, "pool" : pool.address, "context" : "0x"},
        ],
        "tokenOut" : usdc.address,
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };

      let oldAliceWethBalance = await bento.balanceOf(weth.address, alice.address);
      let oldAliceUsdcBalance = await bento.balanceOf(usdc.address, alice.address);
      let oldPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let oldPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      await router.exactInput(params);
      expect(await bento.balanceOf(weth.address, alice.address)).eq(oldAliceWethBalance.sub(amountIn));
      expect(await bento.balanceOf(usdc.address, alice.address)).lt(oldAliceUsdcBalance.add(expectedAmountOutSingleHop));
      expect(await bento.balanceOf(weth.address, pool.address)).eq(oldPoolWethBalance.add(amountIn));
      expect(await bento.balanceOf(usdc.address, pool.address)).gt(oldPoolUsdcBalance.sub(expectedAmountOutSingleHop));
    });

    it("Should add balanced liquidity to unbalanced pool", async function() {
      let initialTotalSupply = await pool.totalSupply();
      let initialPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let initialPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      let liquidityInput = [
        {"token" : weth.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : usdc.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());
      let intermediateTotalSupply = await pool.totalSupply();
      let intermediatePoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let intermediatePoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(intermediateTotalSupply).gt(initialTotalSupply);
      expect(intermediatePoolWethBalance).eq(initialPoolWethBalance.add(BigNumber.from(10).pow(18)));
      expect(intermediatePoolUsdcBalance).gt(initialPoolUsdcBalance);
      expect(intermediatePoolUsdcBalance).lt(initialPoolUsdcBalance.add(BigNumber.from(10).pow(18)));

      // Swap fee deducted
      expect(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).lte(initialPoolWethBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));
      expect(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(intermediateTotalSupply)).lte(initialPoolUsdcBalance.mul(BigNumber.from(10).pow(36)).div(initialTotalSupply));

      liquidityInput = [
        {"token" : usdc.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(18), "amountMin" : 1},
        {"token" : weth.address, "native" : false, "amountDesired" : BigNumber.from(10).pow(17), "amountMin" : 1},
      ];
      await router.addLiquidityBalanced(liquidityInput, pool.address, alice.address, 2 * Date.now());

      let finalTotalSupply = await pool.totalSupply();
      let finalPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let finalPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);

      expect(finalTotalSupply).gt(intermediateTotalSupply);
      expect(finalPoolWethBalance).eq(intermediatePoolWethBalance.add(BigNumber.from(10).pow(17)));
      expect(finalPoolUsdcBalance).gt(intermediatePoolUsdcBalance);
      expect(finalPoolUsdcBalance).lt(intermediatePoolUsdcBalance.add(BigNumber.from(10).pow(17)));

      // Using 18 decimal precision rather than 36 here to accommodate for 1wei rounding errors
      expect(finalPoolWethBalance.mul(BigNumber.from(10).pow(18)).div(finalTotalSupply)).eq(intermediatePoolWethBalance.mul(BigNumber.from(10).pow(18)).div(intermediateTotalSupply));
      expect(finalPoolUsdcBalance.mul(BigNumber.from(10).pow(18)).div(finalTotalSupply)).eq(intermediatePoolUsdcBalance.mul(BigNumber.from(10).pow(18)).div(intermediateTotalSupply));
    });

    it("Should swap some native tokens", async function() {
      let amountIn = BigNumber.from(10).pow(18);
      let expectedAmountOut = await pool.getAmountOut(weth.address, amountIn);
      expect(expectedAmountOut).gt(1);
      let params = {
        "tokenIn" : weth.address,
        "tokenOut" : usdc.address,
        "pool" : pool.address,
        "context" : "0x",
        "recipient" : alice.address,
        "deadline" : 2 * Date.now(),
        "amountIn" : amountIn,
        "amountOutMinimum" : 1
      };

      let oldAliceWethBalance = await weth.balanceOf(alice.address);
      let oldAliceUsdcBalance = await bento.balanceOf(usdc.address, alice.address);
      let oldPoolWethBalance = await bento.balanceOf(weth.address, pool.address);
      let oldPoolUsdcBalance = await bento.balanceOf(usdc.address, pool.address);
      let oldAliceBentoWethBalance = await bento.balanceOf(weth.address, alice.address);

      // multicall
      await router.multicall([
        router.interface.encodeFunctionData("depositToBentoBox", [weth.address, amountIn, pool.address]),
        router.interface.encodeFunctionData("exactInputSingleWithPreFunding", [params])
      ]);

      expect(await weth.balanceOf(alice.address)).eq(oldAliceWethBalance.sub(amountIn));
      expect(await bento.balanceOf(usdc.address, alice.address)).eq(oldAliceUsdcBalance.add(expectedAmountOut));
      expect(await bento.balanceOf(weth.address, pool.address)).eq(oldPoolWethBalance.add(amountIn));
      expect(await bento.balanceOf(usdc.address, pool.address)).eq(oldPoolUsdcBalance.sub(expectedAmountOut));
      expect(await bento.balanceOf(weth.address, alice.address)).eq(oldAliceBentoWethBalance);

      amountIn = expectedAmountOut;
      expectedAmountOut = await pool.getAmountOut(usdc.address, amountIn);
      expect(expectedAmountOut).lt(BigNumber.from(10).pow(18));
      params = {
        "tokenIn" : usdc.address,
        "tokenOut" : weth.address,
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
      expect(await bento.balanceOf(weth.address, pool.address)).gt(oldPoolWethBalance);
      expect(await bento.balanceOf(usdc.address, pool.address)).eq(oldPoolUsdcBalance);
    });
  });
})

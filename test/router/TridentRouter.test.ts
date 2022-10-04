import { ADDRESS_ZERO, customError } from "../utilities";
import { BentoBoxV1, ERC20Mock, TridentRouter, WETH9 } from "../../types";
import { deployments, ethers, getChainId } from "hardhat";
import { initializedConstantProductPool, uninitializedConstantProductPool } from "../fixtures";

import { expect } from "chai";
import { getSignedMasterContractApprovalData } from "../utilities/bentobox";

describe("Router", function () {
  before(async function () {
    await deployments.fixture(["TridentRouter"]);
  });

  beforeEach(async function () {
    //
  });

  describe("receive()", function () {
    it("Succeeds when msg.sender is WETH", async () => {
      const router = await ethers.getContract<TridentRouter>("TridentRouter");
      const weth9 = await ethers.getContract<WETH9>("WETH9");
      const deployer = await ethers.getNamedSigner("deployer");
      await expect(weth9.transfer(router.address, 1)).to.not.be.reverted;
      await expect(router.unwrapWETH(deployer.address)).to.not.be.reverted;
    });
    it("Reverts when msg.sender is not WETH", async () => {
      const router = await ethers.getContract<TridentRouter>("TridentRouter");
      const deployer = await ethers.getNamedSigner("deployer");
      await expect(
        deployer.sendTransaction({
          from: deployer.address,
          to: router.address,
          value: ethers.utils.parseEther("1"),
        })
      ).to.be.revertedWith("NotWethSender");
    });
  });

  describe("#exactInputSingle", function () {
    //
    it("Reverts when output is less than minimum", async () => {
      const router = await ethers.getContract<TridentRouter>("TridentRouter");

      const pool = await initializedConstantProductPool();

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const deployer = await ethers.getNamedSigner("deployer");

      await token0.approve(bento.address, "1000000000000000000");
      await bento.deposit(token0.address, deployer.address, deployer.address, "1000000000000000000", "0");

      await bento.whitelistMasterContract(router.address, true);

      await bento.setMasterContractApproval(
        deployer.address,
        router.address,
        true,
        "0",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      );

      const exactInputSingleParams = {
        amountIn: "1000000000000000000",
        amountOutMinimum: "1000000000000000000",
        pool: pool.address,
        tokenIn: token0.address,
        data: ethers.utils.defaultAbiCoder.encode(
          ["address", "address", "bool"],
          [token0.address, deployer.address, false]
        ), // (address tokenIn, address recipient, bool unwrapBento) = abi.decode(data, (address, address, bool));
      };

      await expect(router.exactInputSingle(exactInputSingleParams)).to.be.revertedWith(
        customError("TooLittleReceived")
      );
    });
  });

  describe("#exactInput", function () {
    //
  });

  describe("#exactInputLazy", function () {
    //
  });

  describe("#exactInputSingleWithNativeToken", function () {
    //
  });

  describe("#exactInputWithNativeToken", function () {
    //
  });

  describe("#complexPath", function () {
    //
  });

  describe("#addLiquidity", function () {
    it("Reverts when not enough liquidity is minted", async () => {
      const deployer = await ethers.getNamedSigner("deployer");

      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const router = await ethers.getContract<TridentRouter>("TridentRouter");

      await bentoBox.whitelistMasterContract(router.address, true);

      const pool = await initializedConstantProductPool();

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      await token0.approve(bentoBox.address, 1);
      await token1.approve(bentoBox.address, 1);

      await bentoBox.setMasterContractApproval(
        deployer.address,
        router.address,
        true,
        "0",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      );

      const liquidityInput = [
        {
          token: token0.address,
          native: true,
          amount: 1,
        },
        {
          token: token1.address,
          native: true,
          amount: 1,
        },
      ];

      await expect(
        router.addLiquidity(
          liquidityInput,
          pool.address,
          1000,
          ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address])
        )
      ).to.be.revertedWith("NotEnoughLiquidityMinted");
    });

    it("Reverts when update overflows", async () => {
      const deployer = await ethers.getNamedSigner("deployer");

      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const router = await ethers.getContract<TridentRouter>("TridentRouter");

      await bentoBox.whitelistMasterContract(router.address, true);

      const pool = await initializedConstantProductPool();

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());
      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      await token0.approve(bentoBox.address, ethers.BigNumber.from(2).pow(112));
      await token1.approve(bentoBox.address, 1);

      await bentoBox.setMasterContractApproval(
        deployer.address,
        router.address,
        true,
        "0",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      );

      const liquidityInput = [
        {
          token: token0.address,
          native: true,
          amount: ethers.BigNumber.from(2).pow(112),
        },
        {
          token: token1.address,
          native: true,
          amount: 1,
        },
      ];

      await expect(
        router.addLiquidity(
          liquidityInput,
          pool.address,
          1000,
          ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address])
        )
      ).to.be.revertedWith("Overflow()");
    });
  });

  describe("#burnLiquidity", function () {
    it("Reverts when an incorrect token order for minWithdrawals is sent", async () => {
      const deployer = await ethers.getNamedSigner("deployer");

      const router = await ethers.getContract<TridentRouter>("TridentRouter");

      const pool = await initializedConstantProductPool();

      const balance = await pool.balanceOf(deployer.address);

      await pool.approve(router.address, balance);

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      const data = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [deployer.address, false]);

      const minWithdrawals = [
        {
          token: token1.address,
          amount: "0",
        },
        {
          token: token0.address,
          amount: "0",
        },
      ];

      await expect(router.burnLiquidity(pool.address, balance, data, minWithdrawals)).to.be.revertedWith(
        "IncorrectSlippageParams"
      );
    });
    it("Reverts when output is less than minimum", async () => {
      const deployer = await ethers.getNamedSigner("deployer");

      const router = await ethers.getContract<TridentRouter>("TridentRouter");

      const pool = await initializedConstantProductPool();

      const balance = await pool.balanceOf(deployer.address);

      await pool.approve(router.address, balance);

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      const token1 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token1());

      const data = ethers.utils.defaultAbiCoder.encode(["address", "bool"], [deployer.address, false]);

      const minWithdrawals = [
        {
          token: token0.address,
          amount: "1000000000000000000",
        },
        {
          token: token1.address,
          amount: "1000000000000000000",
        },
      ];

      await expect(router.burnLiquidity(pool.address, balance, data, minWithdrawals)).to.be.revertedWith(
        "TooLittleReceived"
      );
    });
  });

  describe("#burnLiquiditySingle", function () {
    it("Reverts when output is less than minimum", async () => {
      const deployer = await ethers.getNamedSigner("deployer");

      const router = await ethers.getContract<TridentRouter>("TridentRouter");

      const pool = await initializedConstantProductPool();

      const balance = await pool.balanceOf(deployer.address);

      await pool.approve(router.address, balance);

      console.log("Deployer pool balance", (await pool.balanceOf(deployer.address)).toString());

      const token0 = await ethers.getContractAt<ERC20Mock>("ERC20Mock", await pool.token0());

      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "bool"],
        [token0.address, deployer.address, false]
      );

      // Burn whole balance, expect to get back initial 1000000000000000000 token0, but there wouldn't be enough
      await expect(router.burnLiquiditySingle(pool.address, balance, data, "1000000000000000000")).to.be.revertedWith(
        "TooLittleReceived"
      );
    });
  });

  describe("#sweep", function () {
    it("Allows sweep of bentobox erc20 token", async () => {
      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
      const router = await ethers.getContract<TridentRouter>("TridentRouter");
      const weth9 = await ethers.getContract<WETH9>("WETH9");
      const deployer = await ethers.getNamedSigner("deployer");
      await weth9.approve(bentoBox.address, 1);
      await bentoBox.deposit(weth9.address, deployer.address, router.address, 0, 1);
      await router.sweep(weth9.address, deployer.address, true);
      expect(await bentoBox.balanceOf(weth9.address, deployer.address)).equal(1);
    });
    it("Allows sweep of native eth", async () => {
      const router = await ethers.getContract<TridentRouter>("TridentRouter");
      const carol = await ethers.getNamedSigner("carol");
      const balance = await carol.getBalance();

      // Gifting 100 unit and sweeping it back
      await router.sweep(ADDRESS_ZERO, carol.address, false, { value: 100 });
      // Balance should be plus 99, since the deployer gifted 100 unit and carol sweeped it
      // but 1 unit is kept inside router to avoid cold storage
      expect(await carol.getBalance()).equal(balance.add(99));
    });
    it("Allows sweeps of regular erc20 token", async () => {
      const router = await ethers.getContract<TridentRouter>("TridentRouter");
      const weth9 = await ethers.getContract<WETH9>("WETH9");
      const deployer = await ethers.getNamedSigner("deployer");
      const balance = await weth9.balanceOf(deployer.address);
      // Gifting 10 unit of WETH
      await weth9.transfer(router.address, 10);
      // Sweeping it back
      await router.sweep(weth9.address, deployer.address, false);
      // Balance should remain the same, minus 1
      expect(await weth9.balanceOf(deployer.address)).equal(balance.sub(1));
    });
  });

  describe("#unwrapWETH", function () {
    it("Correctly unwraps weth", async () => {
      const router = await ethers.getContract<TridentRouter>("TridentRouter");
      const weth9 = await ethers.getContract<WETH9>("WETH9");
      await weth9.transfer(router.address, 1);
      const difference = await weth9.balanceOf(router.address);
      const oldBalance = await ethers.provider.getBalance(ethers.constants.AddressZero);
      await expect(router.unwrapWETH(ethers.constants.AddressZero)).to.not.be.reverted;
      const newBalance = await ethers.provider.getBalance(ethers.constants.AddressZero);
      expect(oldBalance.add(difference).eq(newBalance)).to.be.true;
    });
  });

  describe("#approveMasterContract", function () {
    it("Succeed setting master contract approval on bentobox", async () => {
      const deployer = await ethers.getNamedSigner("deployer");

      const chainId = Number(await getChainId());

      const bentoBox = await ethers.getContract<BentoBoxV1>("BentoBoxV1");

      const router = await ethers.getContract<TridentRouter>("TridentRouter");

      await bentoBox.whitelistMasterContract(router.address, true);

      const nonce = await bentoBox.nonces(deployer.address);

      const { v, r, s } = getSignedMasterContractApprovalData(
        bentoBox,
        deployer,
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        router.address,
        true,
        nonce,
        chainId
      );

      await router.approveMasterContract(v, r, s);
    });
  });
});

import { ADDRESS_ZERO, customError } from "../utilities";
import { BentoBoxV1, ConstantProductPool__factory, ERC20Mock, MasterDeployer, TridentRouter, WETH9 } from "../../types";
import { deployments, ethers } from "hardhat";

import { expect } from "chai";
import { initializedConstantProductPool } from "../fixtures";

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
      await expect(router.unwrapWETH(1, deployer.address)).to.not.be.reverted;
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
      ).to.be.revertedWith("Transaction reverted without a reason string");
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
    //
  });

  describe("#addLiquidityLazy", function () {
    //
  });

  describe("#burnLiquidity", function () {
    //
  });

  describe("#burnLiquiditySingle", function () {
    //
  });

  describe("#tridentSwapCallback", function () {
    //
  });

  describe("#tridentMintCallback", function () {
    //
  });

  describe("#sweep", function () {
    it("Allows speed of bentobox erc20 token", async () => {});
    it("Allows sweep of native eth", async () => {
      const router = await ethers.getContract<TridentRouter>("TridentRouter");
      const carol = await ethers.getNamedSigner("carol");
      const balance = await carol.getBalance();
      // Gifting 1 unit and sweeping it back
      await router.sweep(ADDRESS_ZERO, 1, carol.address, false, { value: 1 });
      // Balance should remain the same, since we gifted 1 unit and sweeped it back
      expect(await carol.getBalance()).equal(balance);
    });
    it("Allows sweeps of regular erc20 token", async () => {});
  });

  describe("#unwrapWETH", function () {
    //
  });

  describe("#isWhiteListed", function () {
    //
  });
});

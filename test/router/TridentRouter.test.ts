import { deployments, ethers } from "hardhat";
import { BentoBoxV1, ConstantProductPool__factory, ERC20Mock, MasterDeployer, TridentRouter, WETH9 } from "../../types";
import { expect } from "chai";
import { initializedConstantProductPool } from "../fixtures";
import { customError } from "../utilities";

describe("Constant Product Pool Factory", function () {
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
      await expect(weth9.transfer(router.address, 1)).to.not.be.reverted;
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

  describe("#sweepBentoBoxToken", function () {
    //
  });

  describe("#sweepNativeToken", function () {
    //
  });

  describe("#refundETH", function () {
    //
  });

  describe("#unwrapWETH", function () {
    //
  });

  describe("#isWhiteListed", function () {
    //
  });
});

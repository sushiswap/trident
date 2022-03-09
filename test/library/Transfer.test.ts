import { expect } from "chai";
import { constants, ContractTransaction } from "ethers";
import { ethers } from "hardhat";
import {
  ERC20Compliant,
  ERC20Compliant__factory,
  ERC20Fallback,
  ERC20Fallback__factory,
  ERC20Noncompliant,
  ERC20Noncompliant__factory,
  TransferMock,
  TransferMock__factory,
} from "../../types";

const overrides = {
  gasLimit: 9999999,
};

describe("Transfer", () => {
  let transferMock: TransferMock;
  let erc20Fallback: ERC20Fallback;
  let erc20Noncompliant: ERC20Noncompliant;
  let erc20Compliant: ERC20Compliant;
  before(async () => {
    const TransferMock = await ethers.getContractFactory<TransferMock__factory>("TransferMock");
    transferMock = await TransferMock.deploy(overrides);

    const ERC20Fallback = await ethers.getContractFactory<ERC20Fallback__factory>("ERC20Fallback");
    erc20Fallback = await ERC20Fallback.deploy(overrides);

    const ERC20Noncompliant = await ethers.getContractFactory<ERC20Noncompliant__factory>("ERC20Noncompliant");
    erc20Noncompliant = await ERC20Noncompliant.deploy(overrides);

    const ERC20Compliant = await ethers.getContractFactory<ERC20Compliant__factory>("ERC20Compliant");
    erc20Compliant = await ERC20Compliant.deploy(overrides);
  });

  // sets up the fixtures for each token situation that should be tested
  function harness({
    sendTx,
    expectedError,
  }: {
    sendTx: (tokenAddress: string) => Promise<ContractTransaction>;
    expectedError: string;
  }) {
    it("succeeds with compliant with no revert and true return", async () => {
      await erc20Compliant.setup(true, false);
      await sendTx(erc20Compliant.address);
    });
    it("fails with compliant with no revert and false return", async () => {
      await erc20Compliant.setup(false, false);
      await expect(sendTx(erc20Compliant.address)).to.be.revertedWith(expectedError);
    });
    it("fails with compliant with revert", async () => {
      await erc20Compliant.setup(false, true);
      await expect(sendTx(erc20Compliant.address)).to.be.revertedWith(expectedError);
    });
    it("succeeds with noncompliant (no return) with no revert", async () => {
      await erc20Noncompliant.setup(false);
      await sendTx(erc20Noncompliant.address);
    });
    it("fails with noncompliant (no return) with revert", async () => {
      await erc20Noncompliant.setup(true);
      await expect(sendTx(erc20Noncompliant.address)).to.be.revertedWith(expectedError);
    });
  }

  describe("#safeApprove", () => {
    harness({
      sendTx: (tokenAddress) => transferMock.safeApprove(tokenAddress, constants.AddressZero, constants.MaxUint256),
      expectedError: "SA",
    });
  });
  describe("#safeTransfer", () => {
    harness({
      sendTx: (tokenAddress) => transferMock.safeTransfer(tokenAddress, constants.AddressZero, constants.MaxUint256),
      expectedError: "ST",
    });
  });
  describe("#safeTransferFrom", () => {
    harness({
      sendTx: (tokenAddress) =>
        transferMock.safeTransferFrom(tokenAddress, constants.AddressZero, constants.AddressZero, constants.MaxUint256),
      expectedError: "STF",
    });
  });

  describe("#safeTransferETH", () => {
    it("succeeds call not reverted", async () => {
      await erc20Fallback.setup(false);
      await transferMock.safeTransferETH(erc20Fallback.address, 0);
    });
    it("fails if call reverts", async () => {
      await erc20Fallback.setup(true);
      await expect(transferMock.safeTransferETH(erc20Fallback.address, 0)).to.be.revertedWith("STE");
    });
  });
});

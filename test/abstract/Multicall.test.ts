import { Wallet } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { MulticallMock, MulticallMock__factory } from "../../types";
import { snapshotGasCost } from "../utilities";

describe("Multicall", async () => {
  let wallets: Wallet[];

  let multicall: MulticallMock;

  before("get wallets", async () => {
    wallets = await (ethers as any).getSigners();
  });

  beforeEach("create multicall", async () => {
    const MulticallMockFactory = await ethers.getContractFactory<MulticallMock__factory>("MulticallMock");
    multicall = await MulticallMockFactory.deploy();
  });

  it("revert messages are returned", async () => {
    await expect(
      multicall.multicall([multicall.interface.encodeFunctionData("functionThatRevertsWithError", ["abcdef"])])
    ).to.be.revertedWith("abcdef");
  });

  it("revert when result is less than 68", async () => {
    await expect(multicall.multicall([multicall.interface.encodeFunctionData("functionThatRevertsWithoutError")])).to.be
      .reverted;
  });

  it("return data is properly encoded", async () => {
    const [data] = await multicall.callStatic.multicall([
      multicall.interface.encodeFunctionData("functionThatReturnsTuple", ["1", "2"]),
    ]);
    const {
      tuple: { a, b },
    } = multicall.interface.decodeFunctionResult("functionThatReturnsTuple", data);
    expect(b).to.eq(1);
    expect(a).to.eq(2);
  });

  describe("context is preserved", () => {
    it("msg.value", async () => {
      await multicall.multicall([multicall.interface.encodeFunctionData("pays")], { value: 3 });
      expect(await multicall.paid()).to.eq(3);
    });

    it("msg.value used twice", async () => {
      await multicall.multicall(
        [multicall.interface.encodeFunctionData("pays"), multicall.interface.encodeFunctionData("pays")],
        { value: 3 }
      );
      expect(await multicall.paid()).to.eq(6);
    });

    it("msg.sender", async () => {
      expect(await multicall.returnSender()).to.eq(wallets[0].address);
    });
  });
});

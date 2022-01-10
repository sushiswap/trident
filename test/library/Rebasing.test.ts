import { ethers } from "hardhat";
import { expect } from "chai";
import { RebasingMock, RebasingMock__factory } from "../../types";

describe("Rebasing", () => {
  let mock: RebasingMock;
  before(async () => {
    const RebasingMock = await ethers.getContractFactory<RebasingMock__factory>("RebasingMock");
    mock = await RebasingMock.deploy();
    await mock.deployed();
  });

  beforeEach(async () => {
    await mock.reset();
  });

  it("base is initially 0", async () => {
    const total = await mock.total();
    await expect(total.base).to.equal(0);
  });

  it("elastic is initially 0", async () => {
    const total = await mock.total();
    await expect(total.elastic).to.equal(0);
  });

  describe("#toBase", async () => {
    it("has base:elastic ratio of 1:1 initially", async () => {
      expect(await mock.toBase(100)).to.equal(100);
    });
    it("has base:elastic ratio of 1:2 after setting total to elatic 1000 and base 500", async () => {
      await mock.set(1000, 500);
      expect(await mock.toBase(10)).to.equal(5);
    });
  });

  describe("#toElastic", async () => {
    it("has elastic:base ratio of 1:1 initially", async () => {
      expect(await mock.toElastic(100)).to.equal(100);
    });
    it("has elastic:base ratio of 2:1 after setting total to elatic 1000 and base 500", async () => {
      await mock.set(1000, 500);
      expect(await mock.toElastic(10)).to.equal(20);
    });
  });

  // TODO: Flesh these out a little more...
});

const { expect, assert } = require("chai");
const { ethers } = require("hardhat");

function encodeParameters(types, values) {
    const abi = new ethers.utils.AbiCoder();
    return abi.encode(types, values);
}

describe("Library Test", function () {
    let Test, test, owner, addr1, addr2;

    beforeEach(async function () {
        Test = await ethers.getContractFactory("LibraryTest");
        [owner, addr1, addr2] = await ethers.getSigners();
        test = await Test.deploy();
    });

    it("Strings test", async function () {
        const t1 = await test.uintToString(0);
        const t2 = await test.uintToString(7923);
        expect(t1).to.be.equal("0");
        expect(t1).to.not.equal(0);
        expect(t1).to.be.a("string");
        expect(t2).to.be.equal("7923");
        expect(t2).to.be.a("string");
    });

    it("Address test", async function () {
        const Contract1 = await ethers.getContractFactory("C1");
        const C1 = await Contract1.deploy();
        const Contract2 = await ethers.getContractFactory("C2");
        const C2 = await Contract2.deploy();

        // isContract
        assert.isTrue(await test.isContract(C1.address));
        assert.isFalse(await test.isContract(addr1.address));

        // sendValue
        await expect(test.sendValue(C1.address, 100)).to.be.revertedWith("Address: insufficient balance");
        await owner.sendTransaction({ to: test.address, value: 100000 });
        await expect(test.sendValue(C1.address, 100)).to.be.revertedWith(
            "Address: unable to send value, recipient may have reverted"
        );
        await expect(() => test.sendValue(addr1.address, 100)).to.changeEtherBalances([addr1, test], [100, -100]);

        // functionCall with 2 params
        const data1 = await test.returnCallData("increase(uint256)", encodeParameters(["uint256"], ["100"]));
        const total1 = await C1.total();
        await test.functionCall1(C1.address, data1);
        const total2 = await C1.total();
        await expect(total2 - total1).to.be.equal(100);
        await expect(test.functionCall1(test.address, data1)).to.be.revertedWith("Address: low-level call failed");

        // functionCall with 3 params
        const total3 = await C1.total();
        await test.functionCall2(C1.address, data1, "functionCall2 failed");
        const total4 = await C1.total();
        await expect(total4 - total3).to.be.equal(100);
        await expect(test.functionCall2(test.address, data1, "functionCall2 failed")).to.be.revertedWith(
            "functionCall2 failed"
        );

        // functionCallWithValue with 3 params
        const data2 = await test.returnCallData("increase(uint256)", encodeParameters(["uint256"], ["250"]));
        const total5 = await C2.total();
        await test.functionCallWithValue1(C2.address, data2, 250);
        const total6 = await C2.total();
        await expect(total6 - total5).to.be.equal(250);
        await expect(test.functionCallWithValue1(C2.address, data2, 150)).to.be.revertedWith(
            "Address: low-level call with value failed"
        );

        // functionCallWithValue with 4 params
        const total7 = await C2.total();
        await test.functionCallWithValue2(C2.address, data2, 250, "functionCallWithValue2 failed");
        const total8 = await C2.total();
        await expect(total8 - total7).to.be.equal(250);
        await expect(
            test.functionCallWithValue2(C2.address, data2, 200, "functionCallWithValue2 failed")
        ).to.be.revertedWith("functionCallWithValue2 failed");
        await expect(
            test.functionCallWithValue2(C2.address, data2, 200000000, "functionCallWithValue2 failed")
        ).to.be.revertedWith("Address: insufficient balance for call");

        // additional test
        await expect(
            test.functionCallWithValue2(addr1.address, data2, 250, "functionCallWithValue2 failed")
        ).to.be.revertedWith("Address: call to non-contract");
        const data3 = await test.returnCallData("fail(uint256)", encodeParameters(["uint256"], ["1"]));
        await expect(test.functionCall1(C1.address, data3)).to.be.reverted;
    });

    it("UQ112x112 test", async function () {
        const exp = ethers.BigNumber.from("2").pow(112);
        const t1 = ethers.BigNumber.from(await test.encode(223));
        expect(t1).to.be.equal(ethers.BigNumber.from("223").mul(exp));
        const t2 = ethers.BigNumber.from("2").pow(113);
        const t3 = ethers.BigNumber.from("2").pow(100);
        expect(await test.uqdiv(t2, t3)).to.be.equal(Math.pow(2, 13));
    });
});

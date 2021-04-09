const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

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
        const exp = BigNumber.from("2").pow(112);
        const t1 = BigNumber.from(await test.encode(223));
        expect(t1).to.be.equal(BigNumber.from("223").mul(exp));
        const t2 = BigNumber.from("2").pow(113);
        const t3 = BigNumber.from("2").pow(100);
        expect(await test.uqdiv(t2, t3)).to.be.equal(Math.pow(2, 13));
    });

    it("FixedPoint test", async function () {
        const res = BigNumber.from("2").pow(112);

        // encode
        const t1 = BigNumber.from((await test.encodeFP(1479))[0]);
        expect(t1).to.be.equal(BigNumber.from("1479").mul(res));

        // encode144
        const t2 = BigNumber.from("2").pow(123);
        expect((await test.encode144(t2))[0]).to.be.equal(BigNumber.from(t2).mul(res));
        const t3 = BigNumber.from("2").pow(100);

        // div224By112
        await expect(test.div224By112([t2], 0)).to.be.revertedWith("FixedPoint: DIV_BY_ZERO");
        expect((await test.div224By112([t2], t3))[0]).to.be.equal(Math.pow(2, 23));
        expect((await test.div224By112([12345], 123))[0]).to.be.equal(Math.floor(12345 / 123));

        // mul224To256
        const t4 = BigNumber.from("2").pow(223);
        expect((await test.mul224To256([t2], t3))[0]).to.be.equal(t4);

        // div256By112
        await expect(test.div256By112([t2], 0)).to.be.revertedWith("FixedPoint: DIV_BY_ZERO");
        expect((await test.div256By112([t4], t3))[0]).to.be.equal(t2);

        // mul256To256
        expect((await test.mul256To256([t2], t3))[0]).to.be.equal(t4);

        // fraction
        await expect(test.fraction(t3, 0)).to.be.revertedWith("FixedPoint: DIV_BY_ZERO");
        const t5 = BigNumber.from(t3).mul(res).div("137");
        expect((await test.fraction(t3, 137))[0]).to.be.equal(t5);

        // decode
        expect(await test.decode([t5])).to.be.equal(BigNumber.from(t3).div("137"));

        // decode144
        const t6 = BigNumber.from(t2).mul(res).div("1749");
        expect(await test.decode144([t6])).to.be.equal(BigNumber.from(t2).div("1749"));
    });

    it("SafeERC20 test", async function () {
        const Token = await ethers.getContractFactory("ERC20Token");
        const token = await Token.deploy();

        // safeTransfer
        await token.mint(test.address, 50000);
        await expect(() => test.safeTransfer(token.address, addr1.address, 12345)).to.changeTokenBalances(
            token,
            [test, addr1],
            [-12345, 12345]
        );

        // safeApprove
        await test.safeApprove(token.address, addr1.address, 3333);
        await expect(test.safeApprove(token.address, addr1.address, 1111)).to.be.revertedWith(
            "SafeERC20: approve from non-zero to non-zero allowance"
        );

        // safeTransferFrom
        await token.mint(addr1.address, 50000);
        await token.connect(addr1).approve(test.address, 10000);
        await expect(() =>
            test.safeTransferFrom(token.address, addr1.address, addr2.address, 3000)
        ).to.changeTokenBalances(token, [addr1, addr2], [-3000, 3000]);

        // additional test
        await expect(test.safeTransfer(owner.address, addr1.address, 12345)).to.be.revertedWith(
            "SafeERC20: call to non-contract"
        );
        await expect(test.safeTransfer(token.address, addr1.address, 1234567)).to.be.revertedWith(
            "SafeERC20: low-level call failed"
        );

        const FToken = await ethers.getContractFactory("FakeERC20Token");
        const ftoken = await FToken.deploy();
        await ftoken.mint(test.address, 10000);
        await expect(test.safeTransfer(ftoken.address, addr1.address, 123)).to.be.revertedWith(
            "SafeERC20: ERC20 operation did not succeed"
        );
        await test.safeApprove(ftoken.address, addr1.address, 10);
    });

    it("EnumerableMap test", async function () {
        // set & length
        expect(await test.length()).to.be.equal(0);
        await test.set(13101, owner.address);
        expect(await test.length()).to.be.equal(1);

        // contains
        assert.isTrue(await test.contains(13101));
        assert.isFalse(await test.contains(17));

        for (let i = 1; i < 20; i++) {
            await test.set(13101 + i, addr1.address);
            i++;
            await test.set(13101 + i, addr2.address);
            i++;
            await test.set(13101 + i, owner.address);
        }
        // last number 3n:addr2 3n+1:owner 3n+2:addr1
        // index = key - 13101

        // at
        expect(await test.length()).to.be.equal(22);
        await expect(test.at(25)).to.be.revertedWith("EnumerableMap: index out of bounds");
        const m15 = await test.at(14);
        expect(m15).to.be.eql([BigNumber.from(13115), addr2.address]);

        // get without message
        await expect(test.callStatic["get(uint256)"](13155)).to.be.revertedWith("EnumerableMap: nonexistent key");
        expect(await test.callStatic["get(uint256)"](13122)).to.be.equal(owner.address);

        // get with message
        await expect(test.callStatic["get(uint256,string)"](13155, "get function failed")).to.be.revertedWith(
            "get function failed"
        );
        expect(await test.callStatic["get(uint256,string)"](13121, "get function failed")).to.be.equal(addr2.address);

        // remove
        assert.isFalse(await test.callStatic.remove(1));
        await test.remove(13101); //last key,value(13122,owner) -> array[0]
        expect(await test.length()).to.be.equal(21);
        assert.isFalse(await test.contains(13101));
        let m1 = await test.at(0);
        expect(m1).to.be.eql([BigNumber.from(13122), owner.address]);

        // additional test for set
        assert.isFalse(await test.callStatic.set(13122, addr2.address));
        await test.set(13122, addr2.address);
        m1 = await test.at(0);
        expect(m1).to.be.eql([BigNumber.from(13122), addr2.address]);
    });

    it("EnumerableSet test", async function () {
        // UintSet
        // add&length
        expect(await test.lengthSetUint()).to.be.equal(0);
        await test.addSetUint(100);
        expect(await test.lengthSetUint()).to.be.equal(1);
        for (let i = 1; i <= 30; i++) {
            await test.addSetUint(100 + i);
        } //100~130
        expect(await test.lengthSetUint()).to.be.equal(31);
        assert.isFalse(await test.callStatic.addSetUint(130));

        // contains
        assert.isTrue(await test.containsSetUint(130));
        assert.isFalse(await test.containsSetUint(131));

        // at
        expect(await test.atSetUint(10)).to.be.equal(110);
        await expect(test.atSetUint(100)).to.be.revertedWith("EnumerableSet: index out of bounds");

        // remove
        assert.isFalse(await test.callStatic.removeSetUint(500));
        await test.removeSetUint(110);
        expect(await test.lengthSetUint()).to.be.equal(30);
        assert.isFalse(await test.containsSetUint(110));
        expect(await test.atSetUint(10)).to.be.equal(130);

        // AddressSet
        // add&length
        expect(await test.lengthSetAddr()).to.be.equal(0);
        await test.addSetAddr(owner.address);
        await test.addSetAddr(addr1.address);
        await test.addSetAddr(addr2.address);
        expect(await test.lengthSetAddr()).to.be.equal(3);
        assert.isFalse(await test.callStatic.addSetAddr(owner.address));

        // contains
        assert.isTrue(await test.containsSetAddr(addr1.address));
        assert.isFalse(await test.containsSetAddr(test.address));

        // at
        expect(await test.atSetAddr(0)).to.be.equal(owner.address);
        await expect(test.atSetAddr(100)).to.be.revertedWith("EnumerableSet: index out of bounds");

        // remove
        assert.isFalse(await test.callStatic.removeSetAddr(test.address));
        await test.removeSetAddr(owner.address);
        expect(await test.lengthSetAddr()).to.be.equal(2);
        assert.isFalse(await test.containsSetAddr(owner.address));
        expect(await test.atSetAddr(0)).to.be.equal(addr2.address);
    });

    it("MathUtils test", async function () {
        expect(await test.difference(10, 3)).to.be.equal(7);
        expect(await test.difference(1, 3)).to.be.equal(2);
        assert.isFalse(await test.within1(11, 7));
        assert.isFalse(await test.within1(9, 11));
        assert.isTrue(await test.within1(14, 13));
        assert.isTrue(await test.within1(12, 13));
        assert.isTrue(await test.within1(12, 12));
    });
});

const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils, constants } = require("ethers");

function getData(w0) {
    let d1 = BigNumber.from(w0).toHexString();
    return utils.hexZeroPad(d1, 32);
}

describe("MirinGovernance Test", function () {
    let MF, mf, MP, test, tk0, tk1, CMC, cmc, SUSHI;
    let tx, res;
    const Address0 = constants.AddressZero;

    before(async function () {
        [owner, feeTo, operator, swapFeeTo, addr1, addr2, addr3] = await ethers.getSigners();
        
        const ERC20 = await ethers.getContractFactory("ERC20TestToken");

        SUSHI = await ERC20.deploy();
        tk0 = await ERC20.deploy();
        tk1 = await ERC20.deploy();
        
        CMC = await ethers.getContractFactory("ConstantMeanCurve");
        cmc = await CMC.deploy();
        
        MF = await ethers.getContractFactory("MirinFactory");
        mf = await MF.deploy(SUSHI.address, feeTo.address, owner.address);
        
        await SUSHI.approve(mf.address, BigNumber.from(10).pow(30));
        await mf.whitelistCurve(cmc.address);
    });
    
    beforeEach(async function () {
        let Pool = await mf.callStatic.createPool(tk0.address, tk1.address, cmc.address, getData(20), operator.address, 10, swapFeeTo.address);
        
        await mf.createPool(tk0.address, tk1.address, cmc.address, getData(20), operator.address, 10, swapFeeTo.address);
        
        MP = await ethers.getContractFactory("MirinPool");
        test = await MP.attach(Pool);
    });
    
    it("Should fail unless operator call functions with onlyOperator modifier", async function () {
        expect(await test.callStatic.operator()).to.be.equal(operator.address);
        await expect(test.setOperator(addr1.address)).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.updateSwapFee(20)).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.updateSwapFeeTo(addr1.address)).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.disable(addr1.address)).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.addToBlacklist([addr1.address, addr2.address])).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.removeFromBlacklist([addr1.address, addr2.address])).to.be.revertedWith("MIRIN: UNAUTHORIZED");
    });

    it("Should fail when newOperator address is zero", async function () {
        await expect(test.connect(operator).setOperator(Address0)).to.be.revertedWith("MIRIN: INVALID_OPERATOR");
    });

    it("Should change operator and emit event", async function () {
        tx = await test.connect(operator).setOperator(addr1.address);
        res = await tx.wait();

        expect(res.events[0].event).to.be.equal("OperatorSet");
        expect(res.events[0].args[0]).to.be.equal(operator.address);
        expect(res.events[0].args[1]).to.be.equal(addr1.address);
        expect(await test.callStatic.operator()).to.be.equal(addr1.address);
    });

    it("Should fail when newFee is out of range", async function () {
        await expect(test.connect(operator).updateSwapFee(0)).to.be.revertedWith("MIRIN: INVALID_SWAP_FEE");
        await expect(test.connect(operator).updateSwapFee(101)).to.be.revertedWith("MIRIN: INVALID_SWAP_FEE");
    });

    it("Should update swapFee and emit event", async function () {
        expect(await test.swapFee()).to.be.equal(10);
    
        tx = await test.connect(operator).updateSwapFee(30);
        res = await tx.wait();

        expect(res.events[0].event).to.be.equal("SwapFeeUpdated");
        expect(res.events[0].args[0]).to.be.equal(30);
        expect(await test.swapFee()).to.be.equal(30);
    });

    it("Should update swapFeeTo and emit event", async function () {
        expect(await test.swapFeeTo()).to.be.equal(swapFeeTo.address);
    
        tx = await test.connect(operator).updateSwapFeeTo(addr1.address);
        res = await tx.wait();

        expect(res.events[0].event).to.be.equal("SwapFeeToUpdated");
        expect(res.events[0].args[0]).to.be.equal(addr1.address);
        expect(await test.swapFeeTo()).to.be.equal(addr1.address);
    });

    it("Should disable pool and refund SUSHI_deposit", async function () {
        expect(await mf.isPool(test.address)).to.be.true;
    
        await expect(() => test.connect(operator).disable(addr1.address)).to.changeTokenBalance(SUSHI, addr1, BigNumber.from(10).pow(18).mul(10000));
      
        expect(await mf.isPool(test.address)).to.be.false;
    });

    it("Should add and remove given addresses into/from blacklists and emit events", async function () {
        expect(await test.blacklisted(addr1.address)).to.be.false;
        expect(await test.blacklisted(addr2.address)).to.be.false;
        expect(await test.blacklisted(addr3.address)).to.be.false;
    
        tx = await test.connect(operator).addToBlacklist([addr1.address, addr2.address, addr3.address]);
        res = await tx.wait();

        expect(res.events[0].event).to.be.equal("BlacklistAdded");
        expect(res.events[0].args[0]).to.be.equal(addr1.address);
        expect(res.events[1].args[0]).to.be.equal(addr2.address);
        expect(res.events[2].args[0]).to.be.equal(addr3.address);

        expect(await test.blacklisted(addr1.address)).to.be.true;
        expect(await test.blacklisted(addr2.address)).to.be.true;
        expect(await test.blacklisted(addr3.address)).to.be.true;
    
        tx = await test.connect(operator).removeFromBlacklist([addr1.address, addr2.address]);
        res = await tx.wait();

        expect(res.events[0].event).to.be.equal("BlacklistRemoved");
        expect(res.events[0].args[0]).to.be.equal(addr1.address);
        expect(res.events[1].args[0]).to.be.equal(addr2.address);

        expect(await test.blacklisted(addr1.address)).to.be.false;
        expect(await test.blacklisted(addr2.address)).to.be.false;
        expect(await test.blacklisted(addr3.address)).to.be.true;
    });

    it("Should fail if an address on blacklists call function with notBlacklisted modifier", async function () {
        await test.connect(operator).addToBlacklist([addr1.address]);
        
        await tk0.transfer(test.address, 100000);
        await tk1.transfer(test.address, 100000);

        await expect(test.mint(addr1.address)).to.be.revertedWith("MIRIN: BLACKLISTED");

        await test.mint(addr2.address);
    });

    it("Should be that swapFee is 3 and swapFeeTo is zero when operator is zero address", async function () {
        let Pool = await mf.callStatic.createPool(tk0.address, tk1.address, cmc.address, getData(20), Address0, 10, swapFeeTo.address);

        await mf.createPool(tk0.address, tk1.address, cmc.address, getData(20), Address0, 10, swapFeeTo.address);

        MP = await ethers.getContractFactory("MirinPool");
        test = await MP.attach(Pool);

        expect(await test.callStatic.operator()).to.be.equal(Address0);
        expect(await test.swapFee()).to.be.equal(3);
        expect(await test.swapFeeTo()).to.be.equal(Address0);
    });
});
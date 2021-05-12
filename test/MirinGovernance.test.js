const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils, constants } = ethers;
const { AddressZero } = constants;

describe("MirinGovernance Test", function () {
    let owner, feeTo, operator, swapFeeTo, addr1, addr2, addr3;
    let ERC20, factory, test, curve, sushi, token0, token1;

    function getData(w0) {
        let d1 = BigNumber.from(w0).toHexString();
        return utils.hexZeroPad(d1, 32);
    }

    async function getPool(tk0Addr, tk1Addr, curveAddr, curvedata, operatorAddr, fee, feeToAddr) {
        await factory.createPool(tk0Addr, tk1Addr, curveAddr, curvedata, operatorAddr, fee, feeToAddr);

        const eventFilter = factory.filters.PoolCreated();
        const events = await factory.queryFilter(eventFilter, "latest");

        const Pool = await ethers.getContractFactory("MirinPool");
        return await Pool.attach(events[0].args[4]);
    }

    before(async function () {
        [owner, feeTo, operator, swapFeeTo, addr1, addr2, addr3] = await ethers.getSigners();
        ERC20 = await ethers.getContractFactory("ERC20TestToken");
        sushi = await ERC20.deploy();
        token0 = await ERC20.deploy();
        token1 = await ERC20.deploy();

        const ConstantMeanCurve = await ethers.getContractFactory("ConstantMeanCurve");
        curve = await ConstantMeanCurve.deploy();

        const Factory = await ethers.getContractFactory("MirinFactory");
        factory = await Factory.deploy(sushi.address, feeTo.address, owner.address);

        await sushi.approve(factory.address, BigNumber.from(10).pow(30));
        await factory.whitelistCurve(curve.address);
    });

    beforeEach(async function () {
        test = await getPool(
            token0.address,
            token1.address,
            curve.address,
            getData(20),
            operator.address,
            10,
            swapFeeTo.address
        );
    });

    it("Should fail unless operator call functions with onlyOperator modifier", async function () {
        expect(await test.callStatic.operator()).to.be.equal(operator.address);
        await expect(test.setOperator(addr1.address)).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.updateSwapFee(20)).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.updateSwapFeeTo(addr1.address)).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.disable(addr1.address)).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.addToWhitelist([addr1.address, addr2.address])).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        await expect(test.removeFromWhitelist([addr1.address, addr2.address])).to.be.revertedWith(
            "MIRIN: UNAUTHORIZED"
        );
    });

    it("Should fail when newOperator address is zero", async function () {
        await expect(test.connect(operator).setOperator(AddressZero)).to.be.revertedWith("MIRIN: INVALID_OPERATOR");
    });

    it("Should change operator and emit event", async function () {
        const tx = await test.connect(operator).setOperator(addr1.address);
        const res = await tx.wait();

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

        const tx = await test.connect(operator).updateSwapFee(30);
        const res = await tx.wait();

        expect(res.events[0].event).to.be.equal("SwapFeeUpdated");
        expect(res.events[0].args[0]).to.be.equal(30);
        expect(await test.swapFee()).to.be.equal(30);
    });

    it("Should update swapFeeTo and emit event", async function () {
        expect(await test.swapFeeTo()).to.be.equal(swapFeeTo.address);

        const tx = await test.connect(operator).updateSwapFeeTo(addr1.address);
        const res = await tx.wait();

        expect(res.events[0].event).to.be.equal("SwapFeeToUpdated");
        expect(res.events[0].args[0]).to.be.equal(addr1.address);
        expect(await test.swapFeeTo()).to.be.equal(addr1.address);
    });

    it("Should disable pool and refund SUSHI_deposit", async function () {
        expect(await factory.isPool(test.address)).to.be.true;

        await expect(() => test.connect(operator).disable(addr1.address)).to.changeTokenBalance(
            sushi,
            addr1,
            BigNumber.from(10).pow(18).mul(10000)
        );

        expect(await factory.isPool(test.address)).to.be.false;
    });

    it("Should add and remove given addresses into/from whitelist and emit events", async function () {
        expect(await test.whitelisted(addr1.address)).to.be.false;
        expect(await test.whitelisted(addr2.address)).to.be.false;
        expect(await test.whitelisted(addr3.address)).to.be.false;

        let tx = await test.connect(operator).addToWhitelist([addr1.address, addr2.address, addr3.address]);
        let res = await tx.wait();

        expect(res.events[0].event).to.be.equal("WhitelistAdded");
        expect(res.events[0].args[0]).to.be.equal(addr1.address);
        expect(res.events[1].args[0]).to.be.equal(addr2.address);
        expect(res.events[2].args[0]).to.be.equal(addr3.address);

        expect(await test.whitelisted(addr1.address)).to.be.true;
        expect(await test.whitelisted(addr2.address)).to.be.true;
        expect(await test.whitelisted(addr3.address)).to.be.true;

        tx = await test.connect(operator).removeFromWhitelist([addr1.address, addr2.address]);
        res = await tx.wait();

        expect(res.events[0].event).to.be.equal("WhitelistRemoved");
        expect(res.events[0].args[0]).to.be.equal(addr1.address);
        expect(res.events[1].args[0]).to.be.equal(addr2.address);

        expect(await test.whitelisted(addr1.address)).to.be.false;
        expect(await test.whitelisted(addr2.address)).to.be.false;
        expect(await test.whitelisted(addr3.address)).to.be.true;
    });

    it("Should be true that anyone calls function with onlyWhitelisted modifier if whitelist is off", async function () {
        expect(await test.whitelistOn()).to.be.false;
        await test.connect(operator).addToWhitelist([addr1.address]);

        await token0.transfer(test.address, 100000);
        await token1.transfer(test.address, 100000);
        await test.mint(addr1.address);

        await token0.transfer(test.address, 100000);
        await token1.transfer(test.address, 100000);
        await test.mint(addr2.address);
    });


    it("Should fail when whitelist is on and an unwhitelisted address calls function with onlyWhitelisted modifier", async function () {
        expect(await test.whitelistOn()).to.be.false;
        let tx = await test.connect(operator).setWhitelistOn(true);
        let res = await tx.wait();

        expect(res.events[0].event).to.be.equal("WhitelistOnSet");
        expect(res.events[0].args[0]).to.be.equal(true);
        expect(await test.whitelistOn()).to.be.true;

        await test.connect(operator).addToWhitelist([addr1.address]);

        await token0.transfer(test.address, 100000);
        await token1.transfer(test.address, 100000);

        await expect(test.mint(addr2.address)).to.be.revertedWith("MIRIN: NOT_WHITELISTED");
        await test.mint(addr1.address);

        await test.connect(operator).setWhitelistOn(false);
        expect(await test.whitelistOn()).to.be.false;
    });

    it("Should be that swapFee is 3 and swapFeeTo is zero when operator is zero address", async function () {
        test = await getPool(
            token0.address,
            token1.address,
            curve.address,
            getData(20),
            AddressZero,
            10,
            swapFeeTo.address
        );

        expect(await test.callStatic.operator()).to.be.equal(AddressZero);
        expect(await test.swapFee()).to.be.equal(3);
        expect(await test.swapFeeTo()).to.be.equal(AddressZero);
    });
});

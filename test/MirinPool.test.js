const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils, constants, provider } = ethers;
const { AddressZero } = constants;

function rand() {
    const dec = Math.floor(Math.random() * 20) + 3;
    let RA = 0;
    for (let i = 3; i <= dec; i++) {
        let j = Math.floor(Math.random() * 10); //0~9
        if (i === 3 && j === 0) j = 1;
        RA = BigNumber.from(RA).add(BigNumber.from(10).pow(i).mul(j));
    }
    return RA;
}

function getData(w0) {
    let d1 = BigNumber.from(w0).toHexString();
    return utils.hexZeroPad(d1, 32);
}

async function getTs() {
    return (await provider.getBlock()).timestamp;
}

describe("MirinPool Test", function () {
    let owner, feeTo, operator, swapFeeTo, addr1, addr2, addr3;
    let test, token0, token1, curve, factory;

    async function getPool(tk0Addr, tk1Addr, curveAddr, curvedata, operatorAddr, fee, feeToAddr) {
        await factory.createPool(tk0Addr, tk1Addr, curveAddr, curvedata, operatorAddr, fee, feeToAddr);

        const eventFilter = factory.filters.PoolCreated();
        const events = await factory.queryFilter(eventFilter, "latest");

        const Pool = await ethers.getContractFactory("MirinPool");
        return await Pool.attach(events[0].args[4]);
    }

    async function prepare() {
        await token0.transfer(test.address, rand());
        await token1.transfer(test.address, rand());
        await test.mint(addr1.address);
        await token0.transfer(test.address, rand());
        await token1.transfer(test.address, rand());
        await test.mint(addr1.address);
        await token0.transfer(test.address, rand());
        await token1.transfer(test.address, rand());
        await test.mint(addr2.address);
        await token0.transfer(test.address, rand());
        await token1.transfer(test.address, rand());
        await test.mint(addr2.address);

        await token0.transfer(addr1.address, BigNumber.from(2).pow(112));
        await token0.transfer(addr2.address, BigNumber.from(2).pow(112));
        await token1.transfer(addr1.address, BigNumber.from(2).pow(112));
        await token1.transfer(addr2.address, BigNumber.from(2).pow(112));
    }

    async function done() {
        const addr1bal0 = await token0.balanceOf(addr1.address);
        const addr2bal0 = await token0.balanceOf(addr2.address);
        const addr3bal0 = await token0.balanceOf(addr3.address);
        const addr1bal1 = await token1.balanceOf(addr1.address);
        const addr2bal1 = await token1.balanceOf(addr2.address);
        const addr3bal1 = await token1.balanceOf(addr3.address);

        await token0.connect(addr1).transfer(owner.address, addr1bal0);
        await token1.connect(addr1).transfer(owner.address, addr1bal1);
        await token0.connect(addr2).transfer(owner.address, addr2bal0);
        await token1.connect(addr2).transfer(owner.address, addr2bal1);
        await token0.connect(addr3).transfer(owner.address, addr3bal0);
        await token1.connect(addr3).transfer(owner.address, addr3bal1);
    }

    async function randSwap0to1(addr) {
        const tk0bal = await token0.balanceOf(test.address);
        const tk1bal = await token1.balanceOf(test.address);

        let tk0aIn = rand();
        while (tk0aIn.gt(tk0bal.div(2))) {
            tk0aIn = rand();
        }

        const tk1aOut = await curve.computeAmountOut(tk0aIn.mul(4).div(5), tk1bal, tk0bal, getData(20), 3, 1);
        await token0.connect(addr).transfer(test.address, tk0aIn);
        await test.connect(addr).functions["swap(uint256,uint256,address)"](tk1aOut, 0, addr.address);
    }

    async function randSwap1to0(addr) {
        const tk0bal = await token0.balanceOf(test.address);
        const tk1bal = await token1.balanceOf(test.address);

        let tk1aIn = rand();
        while (tk1aIn.gt(tk1bal.div(2))) {
            tk1aIn = rand();
        }

        const tk0aOut = await curve.computeAmountOut(tk1aIn.mul(4).div(5), tk1bal, tk0bal, getData(20), 3, 0);
        await token1.connect(addr).transfer(test.address, tk1aIn);
        await test.connect(addr).functions["swap(uint256,uint256,address)"](0, tk0aOut, addr.address);
    }

    before(async function () {
        [owner, feeTo, operator, swapFeeTo, addr1, addr2, addr3] = await ethers.getSigners();

        const ERC20 = await ethers.getContractFactory("ERC20TestToken");

        const sushi = await ERC20.deploy();
        token0 = await ERC20.deploy();
        token1 = await ERC20.deploy();

        const ConstantMeanCurve = await ethers.getContractFactory("ConstantMeanCurve");
        curve = await ConstantMeanCurve.deploy();

        const Factory = await ethers.getContractFactory("MirinFactory");
        factory = await Factory.deploy(sushi.address, feeTo.address, owner.address);

        await sushi.approve(factory.address, BigNumber.from(10).pow(30));
        await factory.whitelistCurve(curve.address);
    });

    describe("Public Pool Test", function () {
        beforeEach(async function () {
            test = await getPool(token0.address, token1.address, curve.address, getData(20), AddressZero, 0, AddressZero);
        });

        it("Should be reverted when initialized function is called", async function () {
            await expect(
                test.callStatic["initialize(address,address)"](addr1.address, addr2.address)
            ).to.be.revertedWith("MIRIN: NOT_IMPLEMENTED");
        });

        it("Should fail when updateCurveData function is called in Public Constant Mean Curve pool", async function () {
            await expect(test.updateCurveData(getData(10))).to.be.revertedWith("MIRIN: UNAUTHORIZED");
            await expect(test.connect(operator).updateCurveData(getData(10))).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        });

        it("Should fail when re-entrancy attack occurs to functions with lock modifier", async function () {
            const FakeERC20 = await ethers.getContractFactory("FakeERC20Token2");
            const ft = await FakeERC20.deploy();
            test = await getPool(ft.address, token1.address, curve.address, getData(20), AddressZero, 0, AddressZero);

            await expect(test.skim(addr1.address)).to.be.revertedWith("MIRIN: LOCKED");
        });

        it("Should fail when Fake ERC20 token was given to make the pool and safeTransfer function is called", async function () {
            const FakeERC20 = await ethers.getContractFactory("FakeERC20Token");
            const ft = await FakeERC20.deploy();
            test = await getPool(ft.address, token1.address, curve.address, getData(20), AddressZero, 0, AddressZero);
            await ft.mint(test.address, 100000);

            await expect(test.skim(addr1.address)).to.be.revertedWith("MIRIN: TRANSFER_FAILED");
        });

        it("Should fail when invalid curve data is given", async function () {
            await expect(
                factory.createPool(token0.address, token1.address, curve.address, getData(0), AddressZero, 0, AddressZero)
            ).to.be.revertedWith("IN: INVALID_CURVE_DATA");
            await expect(
                factory.createPool(token0.address, token1.address, curve.address, getData(100), AddressZero, 0, AddressZero)
            ).to.be.revertedWith("IN: INVALID_CURVE_DATA");
        });

        it("Should get reserve data and update reserve data via sync function and emit event", async function () {
            let RSV = await test.getReserves();
            expect(RSV[0]).to.be.eq(0);
            expect(RSV[1]).to.be.eq(0);
            expect(RSV[2]).to.be.eq(0);

            await token0.transfer(test.address, 10000);
            await token1.transfer(test.address, 30000);
            const tx = await test.sync();
            const res = await tx.wait();

            expect(token0.address > token1.address).to.be.true;
            expect(await test.token0()).to.be.equal(token1.address);
            expect(await test.token1()).to.be.equal(token0.address);

            RSV = await test.getReserves();
            expect(RSV[0]).to.be.eq(30000);
            expect(RSV[1]).to.be.eq(10000);
            expect(RSV[2]).to.be.eq(await getTs());

            expect(res.events[0].event).to.be.equal("Sync");
            expect(res.events[0].args[0]).to.be.equal(30000);
            expect(res.events[0].args[1]).to.be.equal(10000);

            await token0.transfer(test.address, 1000);
            await token1.transfer(test.address, 3000);
            await test.sync();

            RSV = await test.getReserves();
            expect(RSV[0]).to.be.eq(33000);
            expect(RSV[1]).to.be.eq(11000);
            expect(RSV[2]).to.be.eq(await getTs());
        });

        it("Should not throw error when calculating timeElapsed in case of overflow", async function () {
            await token0.transfer(test.address, 10000);
            await token1.transfer(test.address, 30000);
            await test.sync();

            await provider.send("evm_setNextBlockTimestamp", [2 ** 32 - 1]);
            await test.sync();
            let RSV = await test.getReserves();
            expect(RSV[2]).to.be.eq(await getTs());

            await provider.send("evm_setNextBlockTimestamp", [2 ** 32 + 10]);
            await test.sync();
            RSV = await test.getReserves();
            expect(RSV[2]).to.be.lt(await getTs());
            expect(RSV[2]).to.be.eq(10);
        });

        it("Should calculate price0/1CumulativeLast even in case of overflow", async function () {
            let tmax = 2 ** 32;
            test = await getPool(token0.address, token1.address, curve.address, getData(99), AddressZero, 0, AddressZero);

            await token0.approve(test.address, BigNumber.from(2).pow(256).sub(1));
            await token1.approve(test.address, BigNumber.from(2).pow(256).sub(1));

            await token0.transfer(test.address, BigNumber.from(2).pow(110));
            await token1.transfer(test.address, 1);
            await provider.send("evm_setNextBlockTimestamp", [tmax * 2 - 1]);
            await test.sync();

            expect(await test.price0CumulativeLast()).to.be.eq(0);
            expect(await test.price1CumulativeLast()).to.be.eq(0);

            await token0.transfer(test.address, BigNumber.from(2).pow(110));
            await provider.send("evm_setNextBlockTimestamp", [tmax * 3 - 2]);
            await test.sync();

            let prc = BigNumber.from(2).pow(104);
            let cp0 = BigNumber.from(2)
                .pow(110)
                .mul(99)
                .mul(prc)
                .div(1)
                .div(1)
                .mul(tmax - 1);
            let cp1 = BigNumber.from(1)
                .mul(1)
                .mul(prc)
                .div(BigNumber.from(2).pow(110))
                .div(99)
                .mul(tmax - 1);

            assert.isTrue(cp0.eq(await test.price0CumulativeLast()));
            assert.isTrue(cp1.eq(await test.price1CumulativeLast()));

            await token0.transfer(test.address, BigNumber.from(2).pow(111).sub(1));
            await provider.send("evm_setNextBlockTimestamp", [tmax * 4 - 3]);
            await test.sync();

            cp0 = cp0.add(
                BigNumber.from(2)
                    .pow(111)
                    .mul(99)
                    .mul(prc)
                    .div(1)
                    .div(1)
                    .mul(tmax - 1)
            );
            cp1 = cp1.add(
                BigNumber.from(1)
                    .mul(1)
                    .mul(prc)
                    .div(BigNumber.from(2).pow(111))
                    .div(99)
                    .mul(tmax - 1)
            );
            assert.isTrue(cp0.eq(await test.price0CumulativeLast()));
            assert.isTrue(cp1.eq(await test.price1CumulativeLast()));

            await provider.send("evm_setNextBlockTimestamp", [tmax * 5 - 4]);
            await test.sync();

            cp0 = cp0.add(
                BigNumber.from(2)
                    .pow(112)
                    .sub(1)
                    .mul(99)
                    .mul(prc)
                    .div(1)
                    .div(1)
                    .mul(tmax - 1)
            );
            cp1 = cp1.add(
                BigNumber.from(1)
                    .mul(1)
                    .mul(prc)
                    .div(BigNumber.from(2).pow(112).sub(1))
                    .div(99)
                    .mul(tmax - 1)
            );
            assert.isTrue(cp0.eq(await test.price0CumulativeLast()));
            assert.isTrue(cp1.eq(await test.price1CumulativeLast()));

            await provider.send("evm_setNextBlockTimestamp", [tmax * 6 - 5]);
            await test.sync();

            cp0 = cp0.add(
                BigNumber.from(2)
                    .pow(112)
                    .sub(1)
                    .mul(99)
                    .mul(prc)
                    .div(1)
                    .div(1)
                    .mul(tmax - 1)
            );
            cp1 = cp1.add(
                BigNumber.from(1)
                    .mul(1)
                    .mul(prc)
                    .div(BigNumber.from(2).pow(112).sub(1))
                    .div(99)
                    .mul(tmax - 1)
            );
            assert.isTrue(cp0.gt(BigNumber.from(2).pow(256).sub(1)));
            assert.isTrue(cp0.sub(BigNumber.from(2).pow(256)).eq(await test.price0CumulativeLast()));
            assert.isTrue(cp1.eq(await test.price1CumulativeLast()));
        });

        it("Should fail when balance is more than uint112 while updating reserve data and skim function recover this", async function () {
            await token0.transfer(test.address, BigNumber.from(2).pow(112).sub(1));
            await test.sync();

            await token0.transfer(test.address, 1);
            await expect(test.sync()).to.be.revertedWith("MIRIN: OVERFLOW");

            await expect(() => test.skim(token0.address)).to.changeTokenBalance(token0, token0, 1);
            await test.sync();
        });

        it("Should fail if mint liquidity is less than or equal MINIMUM_LIQUIDITY", async function () {
            await token0.transfer(test.address, 100);
            await token1.transfer(test.address, 1000);
            expect(await curve.computeLiquidity(100, 1000, getData(20))).to.be.lt(1000);
            await expect(test.mint(addr1.address)).to.be.reverted;

            await token0.transfer(test.address, 900);
            expect(await curve.computeLiquidity(1000, 1000, getData(20))).to.be.eq(1000);
            await expect(test.mint(addr1.address)).to.be.revertedWith("MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");

            await token0.transfer(test.address, 200);
            const liq = await curve.computeLiquidity(1200, 1000, getData(20));
            expect(liq).to.be.gt(1000);
            await test.mint(owner.address);

            await expect(test.mint(owner.address)).to.be.revertedWith("MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        });

        it("Should mint LP token well and emit event", async function () {
            const n0 = rand();
            const n1 = rand();
            await token0.transfer(test.address, n0);
            await token1.transfer(test.address, n1);

            expect(await test.balanceOf(AddressZero)).to.be.eq(0);

            const tx = await test.mint(addr1.address);
            const res = await tx.wait();
            const last = res.events.length - 1;

            expect(res.events[last].event).to.be.equal("Mint");
            expect(res.events[last].args[0]).to.be.equal(owner.address);
            expect(res.events[last].args[1]).to.be.equal(n1);
            expect(res.events[last].args[2]).to.be.equal(n0);
            expect(res.events[last].args[3]).to.be.equal(addr1.address);

            expect(await test.balanceOf(AddressZero)).to.be.eq(10 ** 3);
            expect((await curve.computeLiquidity(n1, n0, getData(20))).sub(10 ** 3)).to.be.equal(await test.balanceOf(addr1.address));

            let n2 = rand();
            let n3 = rand();

            let totalSupply = await test.totalSupply();
            let kBefore = await curve.computeLiquidity(n1, n0, getData(20))
            let computed = await curve.computeLiquidity(n1.add(n3), n0.add(n2), getData(20));

            while (kBefore.eq(computed)) {
                n2 += rand();
                n3 += rand();
                computed = await curve.computeLiquidity(n1.add(n3), n0.add(n2), getData(20));
            }

            await token0.transfer(test.address, n2);
            await token1.transfer(test.address, n3);
            await test.mint(addr2.address);

            expect(await test.balanceOf(AddressZero)).to.be.eq(10 ** 3);

            expect(
                computed
                    .sub(kBefore)
                    .mul(totalSupply)
                    .div(kBefore)
                    .eq(await test.balanceOf(addr2.address))
            );

            //token0 100%
            let n4 = rand();
            totalSupply = await test.totalSupply();
            kBefore = computed;
            computed = await curve.computeLiquidity(n1.add(n3), n0.add(n2).add(n4), getData(20));

            while (kBefore.eq(computed)) {
                n4 += rand();
                computed = await curve.computeLiquidity(n1.add(n3), n0.add(n2).add(n4), getData(20));
            }

            await token0.transfer(test.address, n4);
            await test.mint(addr2.address);

            expect(
                computed
                    .sub(kBefore)
                    .mul(totalSupply)
                    .div(kBefore)
                    .eq(await test.balanceOf(addr2.address))
            );

            //token1 100%
            let n5 = rand();
            totalSupply = await test.totalSupply();
            kBefore = computed;
            computed = await curve.computeLiquidity(n1.add(n3).add(n5), n0.add(n2).add(n4), getData(20));

            while (kBefore.eq(computed)) {
                n5 += rand();
                computed = await curve.computeLiquidity(n1.add(n3).add(n5), n0.add(n2).add(n4), getData(20));
            }

            await token1.transfer(test.address, n5);
            await test.mint(addr1.address);

            expect(
                computed
                    .sub(kBefore)
                    .mul(totalSupply)
                    .div(kBefore)
                    .eq(await test.balanceOf(addr2.address))
            );
        });

        it("Should burn LP token well through 'burn(address)' function and emit event", async function () {
            await prepare();

            let balAddr1 = await test.balanceOf(addr1.address);
            await test.connect(addr1).transfer(test.address, balAddr1.div(3));

            let totalSupply = await test.totalSupply();
            let bal0 = await token0.balanceOf(test.address);
            let bal1 = await token1.balanceOf(test.address);
            let liq = await test.balanceOf(test.address);

            let amount0 = liq.mul(bal0).div(totalSupply);
            let amount1 = liq.mul(bal1).div(totalSupply);
            expect(balAddr1.div(3)).to.be.equal(liq);

            const tx = await test.connect(addr1).functions["burn(address)"](addr3.address);
            const res = await tx.wait();
            let last = res.events.length - 1;

            expect(res.events[last].event).to.be.equal("Burn");
            expect(res.events[last].args[0]).to.be.equal(addr1.address);
            expect(res.events[last].args[1]).to.be.equal(amount1);
            expect(res.events[last].args[2]).to.be.equal(amount0);
            expect(res.events[last].args[3]).to.be.equal(addr3.address);

            expect(await token0.balanceOf(addr3.address)).to.be.equal(amount0);
            expect(await token1.balanceOf(addr3.address)).to.be.equal(amount1);

            balAddr1 = await test.balanceOf(addr1.address);
            await test.connect(addr1).transfer(test.address, balAddr1);

            totalSupply = await test.totalSupply();
            bal0 = await token0.balanceOf(test.address);
            bal1 = await token1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);

            const bal0Addr1Before = await token0.balanceOf(addr1.address);
            const bal1Addr1Before = await token1.balanceOf(addr1.address);

            amount0 = liq.mul(bal0).div(totalSupply);
            amount1 = liq.mul(bal1).div(totalSupply);
            expect(balAddr1).to.be.equal(liq);
            await test.connect(addr1).functions["burn(address)"](addr1.address);
            expect(await token0.balanceOf(addr1.address)).to.be.equal(bal0Addr1Before.add(amount0));
            expect(await token1.balanceOf(addr1.address)).to.be.equal(bal1Addr1Before.add(amount1));

            balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(5));

            totalSupply = await test.totalSupply();
            bal0 = await token0.balanceOf(test.address);
            bal1 = await token1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);

            const bal0Addr2Before = await token0.balanceOf(addr2.address);
            const bal1Addr2Before = await token1.balanceOf(addr2.address);

            amount0 = liq.mul(bal0).div(totalSupply);
            amount1 = liq.mul(bal1).div(totalSupply);
            expect(balAddr2.div(5)).to.be.equal(liq);

            await test.connect(addr2).functions["burn(address)"](addr2.address);
            expect(await token0.balanceOf(addr2.address)).to.be.equal(bal0Addr2Before.add(amount0));
            expect(await token1.balanceOf(addr2.address)).to.be.equal(bal1Addr2Before.add(amount1));

            await done();
        });

        it("Should burn LP token well through 'burn(uint256,uint256,address)' function", async function () {
            await prepare();

            let balAddr1 = await test.balanceOf(addr1.address);
            await test.connect(addr1).transfer(test.address, balAddr1.div(5));

            // let totalSupply = await test.totalSupply();
            let bal0 = await token0.balanceOf(test.address);
            let bal1 = await token1.balanceOf(test.address);
            let liq = await test.balanceOf(test.address);
            expect(balAddr1.div(5)).to.be.equal(liq);

            let amounts = await test.connect(addr1).callStatic["burn(address)"](addr1.address);
            let amount0 = amounts[1];
            let amount1 = amounts[0].mul(70).div(100);
            let kBefore = await curve.computeLiquidity(bal1, bal0, getData(20));
            let computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            let totalSupply = await test.totalSupply();
            let liquidityDelta = kBefore.sub(computedLiq).mul(totalSupply).div(kBefore);
            expect(liquidityDelta).to.be.lt(liq);

            let balAddr1Before = await test.balanceOf(addr1.address);
            expect(balAddr1.sub(balAddr1.div(5))).to.be.equal(balAddr1Before);

            let bal0Addr1Before = await token0.balanceOf(addr1.address);
            let bal1Addr1Before = await token1.balanceOf(addr1.address);

            await test.connect(addr1).functions["burn(uint256,uint256,address)"](amount1, amount0, addr1.address);

            let balAddr1After = await test.balanceOf(addr1.address);
            let bal0Addr1After = await token0.balanceOf(addr1.address);
            let bal1Addr1After = await token1.balanceOf(addr1.address);

            expect(balAddr1After).to.be.equal(balAddr1Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr1After).to.be.equal(bal0Addr1Before.add(amount0));
            expect(bal1Addr1After).to.be.equal(bal1Addr1Before.add(amount1));

            let balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(3));

            bal0 = await token0.balanceOf(test.address);
            bal1 = await token1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);
            expect(balAddr2.div(3)).to.be.equal(liq);

            amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            //in case of liqidityDelta < liquidity, it works well even though token0 has more ratio.
            amount0 = amounts[1].mul(105).div(100);
            amount1 = amounts[0].mul(70).div(100);
            kBefore = computedLiq;
            computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            totalSupply = await test.totalSupply();
            liquidityDelta = kBefore.sub(computedLiq).mul(totalSupply).div(kBefore);
            expect(liquidityDelta).to.be.lt(liq);

            let balAddr2Before = await test.balanceOf(addr2.address);
            expect(balAddr2.sub(balAddr2.div(3))).to.be.equal(balAddr2Before);

            let bal0Addr2Before = await token0.balanceOf(addr2.address);
            let bal1Addr2Before = await token1.balanceOf(addr2.address);

            await test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address);

            let balAddr2After = await test.balanceOf(addr2.address);
            let bal0Addr2After = await token0.balanceOf(addr2.address);
            let bal1Addr2After = await token1.balanceOf(addr2.address);

            expect(balAddr2After).to.be.equal(balAddr2Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr2After).to.be.equal(bal0Addr2Before.add(amount0));
            expect(bal1Addr2After).to.be.equal(bal1Addr2Before.add(amount1));

            //in case of liqidityDelta < liquidity, it works well even though token1 has more ratio.
            balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(4));

            bal0 = await token0.balanceOf(test.address);
            bal1 = await token1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);
            expect(balAddr2.div(4)).to.be.equal(liq);

            amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            amount0 = amounts[1].mul(30).div(100);
            amount1 = amounts[0].mul(103).div(100);
            kBefore = computedLiq;
            computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            totalSupply = await test.totalSupply();
            liquidityDelta = kBefore.sub(computedLiq).mul(totalSupply).div(kBefore);
            expect(liquidityDelta).to.be.lt(liq);

            balAddr2Before = await test.balanceOf(addr2.address);
            expect(balAddr2.sub(balAddr2.div(4))).to.be.equal(balAddr2Before);

            bal0Addr2Before = await token0.balanceOf(addr2.address);
            bal1Addr2Before = await token1.balanceOf(addr2.address);

            await test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address);

            balAddr2After = await test.balanceOf(addr2.address);
            bal0Addr2After = await token0.balanceOf(addr2.address);
            bal1Addr2After = await token1.balanceOf(addr2.address);

            expect(balAddr2After).to.be.equal(balAddr2Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr2After).to.be.equal(bal0Addr2Before.add(amount0));
            expect(bal1Addr2After).to.be.equal(bal1Addr2Before.add(amount1));

            //in case of liqidityDelta < liquidity, it works well even though users want to receive token with 100% token0.
            balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(3));

            bal0 = await token0.balanceOf(test.address);
            bal1 = await token1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);
            expect(balAddr2.div(3)).to.be.equal(liq);

            amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            amount0 = amounts[1].mul(110).div(100);
            amount1 = 0;
            kBefore = computedLiq;
            computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            totalSupply = await test.totalSupply();
            liquidityDelta = kBefore.sub(computedLiq).mul(totalSupply).div(kBefore);
            expect(liquidityDelta).to.be.lt(liq);

            balAddr2Before = await test.balanceOf(addr2.address);
            expect(balAddr2.sub(balAddr2.div(3))).to.be.equal(balAddr2Before);

            bal0Addr2Before = await token0.balanceOf(addr2.address);
            bal1Addr2Before = await token1.balanceOf(addr2.address);

            await test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address);

            balAddr2After = await test.balanceOf(addr2.address);
            bal0Addr2After = await token0.balanceOf(addr2.address);
            bal1Addr2After = await token1.balanceOf(addr2.address);

            expect(balAddr2After).to.be.equal(balAddr2Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr2After).to.be.equal(bal0Addr2Before.add(amount0));
            expect(bal1Addr2After).to.be.equal(bal1Addr2Before.add(amount1));

            //in case of liqidityDelta < liquidity, it works well even though users want to receive token with 100% token1.
            balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.mul(2).div(3));

            bal0 = await token0.balanceOf(test.address);
            bal1 = await token1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);
            expect(balAddr2.mul(2).div(3)).to.be.equal(liq);

            amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            amount0 = 0;
            amount1 = amounts[0].mul(111).div(100);
            kBefore = computedLiq;
            computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            totalSupply = await test.totalSupply();
            liquidityDelta = kBefore.sub(computedLiq).mul(totalSupply).div(kBefore);
            expect(liquidityDelta).to.be.lt(liq);

            balAddr2Before = await test.balanceOf(addr2.address);
            expect(balAddr2.sub(balAddr2.mul(2).div(3))).to.be.equal(balAddr2Before);

            bal0Addr2Before = await token0.balanceOf(addr2.address);
            bal1Addr2Before = await token1.balanceOf(addr2.address);

            await test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address);

            balAddr2After = await test.balanceOf(addr2.address);
            bal0Addr2After = await token0.balanceOf(addr2.address);
            bal1Addr2After = await token1.balanceOf(addr2.address);

            expect(balAddr2After).to.be.equal(balAddr2Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr2After).to.be.equal(bal0Addr2Before.add(amount0));
            expect(bal1Addr2After).to.be.equal(bal1Addr2Before.add(amount1));

            await done();
        });

        it("Should fail if both amount0, 1 are zero or users want to withdraw much more tokens they are eligible for withdrawing ", async function () {
            await prepare();

            let balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(3));

            let bal0 = await token0.balanceOf(test.address);
            let bal1 = await token1.balanceOf(test.address);
            let liq = await test.balanceOf(test.address);
            expect(balAddr2.div(3)).to.be.equal(liq);

            let amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            //revert with 0,0
            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](0, 0, addr2.address)
            ).to.be.revertedWith("MIRIN: INVALID_AMOUNTS");

            //revert with much amount. token0 is much more.
            let amount0 = amounts[1].mul(150).div(100);
            let amount1 = amounts[0];

            let kBefore = await curve.computeLiquidity(bal1, bal0, getData(20));
            let computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            let totalSupply = await test.totalSupply();
            let liquidityDelta = kBefore.sub(computedLiq).mul(totalSupply).div(kBefore);
            expect(liquidityDelta).to.be.gt(liq);

            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            //revert with much amount. token1 is much more.
            amount0 = amounts[1];
            amount1 = amounts[0].mul(120).div(100);

            computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            totalSupply = await test.totalSupply();
            liquidityDelta = kBefore.sub(computedLiq).mul(totalSupply).div(kBefore);
            expect(liquidityDelta).to.be.gt(liq);

            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            //revert with much amount. token0 is zero and token1 is much more.
            amount0 = 0;
            amount1 = bal1.mul(9).div(10);

            computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            liquidityDelta = kBefore.sub(computedLiq);
            expect(liquidityDelta).to.be.gt(liq);

            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            //revert with much amount. token1 is zero and token0 is much more.
            amount0 = bal0.mul(9).div(10);
            amount1 = 0;

            computedLiq = await curve.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            totalSupply = await test.totalSupply();
            liquidityDelta = kBefore.sub(computedLiq).mul(totalSupply).div(kBefore);
            expect(liquidityDelta).to.be.gt(liq);

            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            await done();
        });

        it("Should swap from one to the other well and emit event", async function () {
            await prepare();

            await token0.transfer(addr1.address, BigNumber.from(2).pow(112));
            await token0.transfer(addr2.address, BigNumber.from(2).pow(112));
            await token1.transfer(addr1.address, BigNumber.from(2).pow(112));
            await token1.transfer(addr2.address, BigNumber.from(2).pow(112));

            let tk0bal = await token0.balanceOf(test.address);
            let tk1bal = await token1.balanceOf(test.address);

            let tk0aIn0 = rand();
            while (tk0aIn0.gt(tk0bal.div(2))) {
                tk0aIn0 = rand();
            }
            let tk1aOut0 = await curve.computeAmountOut(tk0aIn0, tk1bal, tk0bal, getData(20), 3, 1);
            const exTk1aOut0 = tk1aOut0 < 10 ** 6 ? tk1aOut0.add(10) : tk1aOut0.add(tk1aOut0.div(10 ** 6));

            await token0.connect(addr1).transfer(test.address, tk0aIn0);
            await expect(
                test.functions["swap(uint256,uint256,address)"](exTk1aOut0, 0, addr1.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            let tx = await test.connect(addr1).functions["swap(uint256,uint256,address)"](tk1aOut0, 0, addr1.address);
            let res = await tx.wait();
            let last = res.events.length - 1;

            expect(res.events[last].event).to.be.equal("Swap");
            expect(res.events[last].args[0]).to.be.equal(addr1.address);
            expect(res.events[last].args[1]).to.be.equal(0);
            expect(res.events[last].args[2]).to.be.equal(tk0aIn0);
            expect(res.events[last].args[3]).to.be.equal(tk1aOut0);
            expect(res.events[last].args[4]).to.be.equal(0);
            expect(res.events[last].args[5]).to.be.equal(addr1.address);

            tk0bal = await token0.balanceOf(test.address);
            tk1bal = await token1.balanceOf(test.address);

            let tk0aOut0 = rand();
            while (tk0aOut0.gt(tk0bal.div(3))) {
                tk0aOut0 = rand();
            }
            const exTk0aOut0 = tk0aOut0 < 10 ** 6 ? tk0aOut0.add(10) : tk0aOut0.add(tk0aOut0.div(10 ** 6));

            let tk1aIn0 = await curve.computeAmountIn(tk0aOut0, tk1bal, tk0bal, getData(20), 3, 0);

            await token1.connect(addr1).transfer(test.address, tk1aIn0);
            await expect(
                test.functions["swap(uint256,uint256,address)"](0, exTk0aOut0, addr1.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            tx = await test.connect(addr1).functions["swap(uint256,uint256,address)"](0, tk0aOut0, addr1.address);
            res = await tx.wait();
            last = res.events.length - 1;

            expect(res.events[last].event).to.be.equal("Swap");
            expect(res.events[last].args[0]).to.be.equal(addr1.address);
            expect(res.events[last].args[1]).to.be.equal(tk1aIn0);
            expect(res.events[last].args[2]).to.be.equal(0);
            expect(res.events[last].args[3]).to.be.equal(0);
            expect(res.events[last].args[4]).to.be.equal(tk0aOut0);
            expect(res.events[last].args[5]).to.be.equal(addr1.address);

            await done();
        });

        it("Should fail if given amounts or address to is invalid", async function () {
            await prepare();

            await expect(
                test.functions["swap(uint256,uint256,address)"](0, 0, addr1.address)
            ).to.be.revertedWith("MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");

            const reserve0 = await token0.balanceOf(test.address);
            const reserve1 = await token1.balanceOf(test.address);

            await expect(
                test.functions["swap(uint256,uint256,address)"](0, reserve0.add(1), addr1.address)
            ).to.be.revertedWith("MIRIN: INSUFFICIENT_LIQUIDITY");
            await expect(
                test.functions["swap(uint256,uint256,address)"](reserve1.add(1), 0, addr1.address)
            ).to.be.revertedWith("MIRIN: INSUFFICIENT_LIQUIDITY");

            await expect(
                test.functions["swap(uint256,uint256,address)"](10, 10, token0.address)
            ).to.be.revertedWith("MIRIN: INVALID_TO");
            await expect(
                test.functions["swap(uint256,uint256,address)"](10, 10, token1.address)
            ).to.be.revertedWith("MIRIN: INVALID_TO");

            await expect(
                test.functions["swap(uint256,uint256,address)"](10, 10, addr1.address)
            ).to.be.revertedWith("MIRIN: INSUFFICIENT_INPUT_AMOUNT");

            await done();
        });

        it("Should mint fee well", async function () {
            await prepare();

            const tk0bal0 = await token0.balanceOf(test.address);
            const tk1bal0 = await token1.balanceOf(test.address);

            await randSwap0to1(addr1);
            await randSwap0to1(addr1);
            await randSwap0to1(addr2);
            await randSwap1to0(addr1);
            await randSwap1to0(addr2);
            await randSwap1to0(addr2);

            const tk0bal1 = await token0.balanceOf(test.address);
            const tk1bal1 = await token1.balanceOf(test.address);
            let totalSupply = await test.totalSupply();

            k0 = await curve.computeLiquidity(tk1bal0, tk0bal0, getData(20));
            k1 = await curve.computeLiquidity(tk1bal1, tk0bal1, getData(20));

            let fee = (k1.sub(k0)).mul(totalSupply).div((k1.mul(5)).add(k0));

            await expect(() => test.functions["burn(address)"](addr1.address)).to.changeTokenBalance(test, feeTo, fee.mul(2));
            expect(await test.totalSupply()).to.be.equal(totalSupply.add(fee.mul(2)));
            
            await randSwap1to0(addr2);
            await randSwap1to0(addr2);
            await randSwap1to0(addr1);
            await randSwap1to0(addr2);

            const tk0bal2 = await token0.balanceOf(test.address);
            const tk1bal2 = await token1.balanceOf(test.address);
            totalSupply = await test.totalSupply();

            k2 = await curve.computeLiquidity(tk1bal2, tk0bal2, getData(20));

            fee = (k2.sub(k1)).mul(totalSupply).div((k2.mul(5)).add(k1));

            await expect(() => test.functions["burn(address)"](addr1.address)).to.changeTokenBalance(test, feeTo, fee.mul(2));
            expect(await test.totalSupply()).to.be.equal(totalSupply.add(fee.mul(2)));
            
            await done();
        });
    });
    /*
    describe("Franchised Pool Test", function () {
        beforeEach(async function () {
            test = await getPool(token0.address, token1.address, curve.address, getData(20), operator.address, 10, swapFeeTo.address);
        });
    });
*/
});

const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils, constants, provider } = ethers;

function rand() {
    const dec = Math.floor(Math.random() * 20) + 3;
    let RA = 0;
    for (let i = 3; i <= dec; i++) {
        let j = Math.floor(Math.random() * 10); //0~9
        if (i === 3 && j === 0) j = 1;
        RA = BigNumber.from(RA).add(
            BigNumber.from(10)
                .pow(i)
                .mul(j)
        );
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

describe("MirinPool Test", function() {
    let test, tk0, tk1, cmc, mf, MP;
    const Address0 = constants.AddressZero;

    async function getMP(tk0Addr, tk1Addr, curveAddr, curvedata, operatorAddr, fee, feeToAddr) {
        await mf.createPool(tk0Addr, tk1Addr, curveAddr, curvedata, operatorAddr, fee, feeToAddr);

        const eventFilter = mf.filters.PoolCreated();
        const events = await mf.queryFilter(eventFilter, "latest");
        return await MP.attach(events[0].args[4]);
    }

    before(async function() {
        [owner, feeTo, operator, swapFeeTo, addr1, addr2, addr3] = await ethers.getSigners();

        const ERC20 = await ethers.getContractFactory("ERC20TestToken");

        const sushi = await ERC20.deploy();
        tk0 = await ERC20.deploy();
        tk1 = await ERC20.deploy();

        const CMC = await ethers.getContractFactory("ConstantMeanCurve");
        cmc = await CMC.deploy();

        const MF = await ethers.getContractFactory("MirinFactory");
        mf = await MF.deploy(sushi.address, feeTo.address, owner.address);

        await sushi.approve(mf.address, BigNumber.from(10).pow(30));
        await mf.whitelistCurve(cmc.address);

        MP = await ethers.getContractFactory("MirinPool");
    });

    describe("Public Pool Test", function() {
        beforeEach(async function() {
            test = await getMP(tk0.address, tk1.address, cmc.address, getData(20), Address0, 0, Address0);
        });

        it("Should be reverted when initialized function is called", async function() {
            await expect(
                test.callStatic["initialize(address,address)"](addr1.address, addr2.address)
            ).to.be.revertedWith("MIRIN: NOT_IMPLEMENTED");
        });

        it("Should fail when updateCurveData function is called in Public Constant Mean Curve pool", async function() {
            await expect(test.updateCurveData(getData(10))).to.be.revertedWith("MIRIN: UNAUTHORIZED");
            await expect(test.connect(operator).updateCurveData(getData(10))).to.be.revertedWith("MIRIN: UNAUTHORIZED");
        });

        it("Should fail when re-entrancy attack occurs to functions with lock modifier", async function() {
            const FakeERC20 = await ethers.getContractFactory("FakeERC20Token2");
            const ft = await FakeERC20.deploy();
            test = await getMP(ft.address, tk1.address, cmc.address, getData(20), Address0, 0, Address0);

            await expect(test.skim(addr1.address)).to.be.revertedWith("MIRIN: LOCKED");
        });

        it("Should fail when Fake ERC20 token was given to make the pool and safeTransfer function is called", async function() {
            const FakeERC20 = await ethers.getContractFactory("FakeERC20Token");
            const ft = await FakeERC20.deploy();
            test = await getMP(ft.address, tk1.address, cmc.address, getData(20), Address0, 0, Address0);
            await ft.mint(test.address, 100000);

            await expect(test.skim(addr1.address)).to.be.revertedWith("MIRIN: TRANSFER_FAILED");
        });

        it("Should fail when invalid curve data is given", async function() {
            await expect(
                mf.createPool(tk0.address, tk1.address, cmc.address, getData(0), Address0, 0, Address0)
            ).to.be.revertedWith("IN: INVALID_CURVE_DATA");
            await expect(
                mf.createPool(tk0.address, tk1.address, cmc.address, getData(100), Address0, 0, Address0)
            ).to.be.revertedWith("IN: INVALID_CURVE_DATA");
        });

        it("Should get reserve data and update reserve data via sync function and emit event", async function() {
            let RSV = await test.getReserves();
            expect(RSV[0]).to.be.eq(0);
            expect(RSV[1]).to.be.eq(0);
            expect(RSV[2]).to.be.eq(0);

            await tk0.transfer(test.address, 10000);
            await tk1.transfer(test.address, 30000);
            const tx = await test.sync();
            const res = await tx.wait();

            expect(tk0.address > tk1.address).to.be.true;
            expect(await test.token0()).to.be.equal(tk1.address);
            expect(await test.token1()).to.be.equal(tk0.address);

            RSV = await test.getReserves();
            expect(RSV[0]).to.be.eq(30000);
            expect(RSV[1]).to.be.eq(10000);
            expect(RSV[2]).to.be.eq(await getTs());

            expect(res.events[0].event).to.be.equal("Sync");
            expect(res.events[0].args[0]).to.be.equal(30000);
            expect(res.events[0].args[1]).to.be.equal(10000);

            await tk0.transfer(test.address, 1000);
            await tk1.transfer(test.address, 3000);
            await test.sync();

            RSV = await test.getReserves();
            expect(RSV[0]).to.be.eq(33000);
            expect(RSV[1]).to.be.eq(11000);
            expect(RSV[2]).to.be.eq(await getTs());
        });

        it("Should not throw error when calculating timeElapsed in case of overflow", async function() {
            await tk0.transfer(test.address, 10000);
            await tk1.transfer(test.address, 30000);
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

        it("Should calculate price0/1CumulativeLast even in case of overflow", async function() {
            let tmax = 2 ** 32;
            test = await getMP(tk0.address, tk1.address, cmc.address, getData(99), Address0, 0, Address0);

            await tk0.approve(
                test.address,
                BigNumber.from(2)
                    .pow(256)
                    .sub(1)
            );
            await tk1.approve(
                test.address,
                BigNumber.from(2)
                    .pow(256)
                    .sub(1)
            );

            await tk0.transfer(test.address, BigNumber.from(2).pow(110));
            await tk1.transfer(test.address, 1);
            await provider.send("evm_setNextBlockTimestamp", [tmax * 2 - 1]);
            await test.sync();

            expect(await test.price0CumulativeLast()).to.be.eq(0);
            expect(await test.price1CumulativeLast()).to.be.eq(0);

            await tk0.transfer(test.address, BigNumber.from(2).pow(110));
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

            await tk0.transfer(
                test.address,
                BigNumber.from(2)
                    .pow(111)
                    .sub(1)
            );
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
                    .div(
                        BigNumber.from(2)
                            .pow(112)
                            .sub(1)
                    )
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
                    .div(
                        BigNumber.from(2)
                            .pow(112)
                            .sub(1)
                    )
                    .div(99)
                    .mul(tmax - 1)
            );
            assert.isTrue(
                cp0.gt(
                    BigNumber.from(2)
                        .pow(256)
                        .sub(1)
                )
            );
            assert.isTrue(cp0.sub(BigNumber.from(2).pow(256)).eq(await test.price0CumulativeLast()));
            assert.isTrue(cp1.eq(await test.price1CumulativeLast()));
        });

        it("Should fail when balance is more than uint112 while updating reserve data and skim function recover this", async function() {
            await tk0.transfer(
                test.address,
                BigNumber.from(2)
                    .pow(112)
                    .sub(1)
            );
            await test.sync();

            await tk0.transfer(test.address, 1);
            await expect(test.sync()).to.be.revertedWith("MIRIN: OVERFLOW");

            await expect(() => test.skim(tk0.address)).to.changeTokenBalance(tk0, tk0, 1);
            await test.sync();
        });

        it("Should fail if mint liquidity is less than or equal MINIMUM_LIQUIDITY", async function() {
            await tk0.transfer(test.address, 100);
            await tk1.transfer(test.address, 1000);
            expect(await cmc.computeLiquidity(100, 1000, getData(20))).to.be.lt(1000);
            await expect(test.mint(addr1.address)).to.be.reverted;

            await tk0.transfer(test.address, 900);
            expect(await cmc.computeLiquidity(1000, 1000, getData(20))).to.be.eq(1000);
            await expect(test.mint(addr1.address)).to.be.revertedWith("MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");

            await tk0.transfer(test.address, 200);
            const liq = await cmc.computeLiquidity(1200, 1000, getData(20));
            expect(liq).to.be.gt(1000);
            await test.mint(owner.address);

            await expect(test.mint(owner.address)).to.be.revertedWith("MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        });

        it("Should mint LP token well and emit event", async function() {
            const n0 = rand();
            const n1 = rand();
            await tk0.transfer(test.address, n0);
            await tk1.transfer(test.address, n1);

            expect(await test.balanceOf(Address0)).to.be.eq(0);

            const tx = await test.mint(addr1.address);
            const res = await tx.wait();
            const last = res.events.length - 1;

            expect(res.events[last].event).to.be.equal("Mint");
            expect(res.events[last].args[0]).to.be.equal(owner.address);
            expect(res.events[last].args[1]).to.be.equal(n1);
            expect(res.events[last].args[2]).to.be.equal(n0);
            expect(res.events[last].args[3]).to.be.equal(addr1.address);

            expect(await test.balanceOf(Address0)).to.be.eq(10 ** 3);
            assert.isTrue(
                (await cmc.computeLiquidity(n1, n0, getData(20))).sub(10 ** 3).eq(await test.balanceOf(addr1.address))
            );

            const n2 = rand();
            const n3 = rand();
            await tk0.transfer(test.address, n2);
            await tk1.transfer(test.address, n3);
            await test.mint(addr2.address);

            expect(await test.balanceOf(Address0)).to.be.eq(10 ** 3);
            let totalSupply = await test.totalSupply();
            let kLast = await test.kLast();
            let computed = await cmc.computeLiquidity(n1.add(n3), n0.add(n2), getData(20));

            expect(
                computed
                    .sub(kLast)
                    .mul(totalSupply)
                    .div(kLast)
                    .eq(await test.balanceOf(addr2.address))
            );

            //token0 100%
            const n4 = rand();
            await tk0.transfer(test.address, n4);
            await test.mint(addr2.address);
            totalSupply = await test.totalSupply();
            kLast = await test.kLast();
            computed = await cmc.computeLiquidity(n1.add(n3), n0.add(n2).add(n4), getData(20));

            expect(
                computed
                    .sub(kLast)
                    .mul(totalSupply)
                    .div(kLast)
                    .eq(await test.balanceOf(addr2.address))
            );

            //token1 100%
            const n5 = rand();
            await tk1.transfer(test.address, n5);
            await test.mint(addr1.address);
            totalSupply = await test.totalSupply();
            kLast = await test.kLast();
            computed = await cmc.computeLiquidity(n1.add(n3).add(n5), n0.add(n2).add(n4), getData(20));

            expect(
                computed
                    .sub(kLast)
                    .mul(totalSupply)
                    .div(kLast)
                    .eq(await test.balanceOf(addr2.address))
            );
        }); //TODO : mintFee test.

        it("Should burn LP token well through 'burn(address)' function and emit event", async function() {
            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr1.address);

            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr2.address);

            let balAddr1 = await test.balanceOf(addr1.address);
            await test.connect(addr1).transfer(test.address, balAddr1.div(3));

            let totalSupply = await test.totalSupply();
            let bal0 = await tk0.balanceOf(test.address);
            let bal1 = await tk1.balanceOf(test.address);
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

            expect(await tk0.balanceOf(addr3.address)).to.be.equal(amount0);
            expect(await tk1.balanceOf(addr3.address)).to.be.equal(amount1);

            balAddr1 = await test.balanceOf(addr1.address);
            await test.connect(addr1).transfer(test.address, balAddr1);

            totalSupply = await test.totalSupply();
            bal0 = await tk0.balanceOf(test.address);
            bal1 = await tk1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);

            amount0 = liq.mul(bal0).div(totalSupply);
            amount1 = liq.mul(bal1).div(totalSupply);
            expect(balAddr1).to.be.equal(liq);
            await test.connect(addr1).functions["burn(address)"](addr1.address);
            expect(await tk0.balanceOf(addr1.address)).to.be.equal(amount0);
            expect(await tk1.balanceOf(addr1.address)).to.be.equal(amount1);

            balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(5));

            totalSupply = await test.totalSupply();
            bal0 = await tk0.balanceOf(test.address);
            bal1 = await tk1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);

            amount0 = liq.mul(bal0).div(totalSupply);
            amount1 = liq.mul(bal1).div(totalSupply);
            expect(balAddr2.div(5)).to.be.equal(liq);

            await test.connect(addr2).functions["burn(address)"](addr2.address);
            expect(await tk0.balanceOf(addr2.address)).to.be.equal(amount0);
            expect(await tk1.balanceOf(addr2.address)).to.be.equal(amount1);
        });

        it("Should burn LP token well through 'burn(uint256,uint256,address)' function", async function() {
            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr1.address);

            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr2.address);

            let balAddr1 = await test.balanceOf(addr1.address);
            await test.connect(addr1).transfer(test.address, balAddr1.div(5));

            // let totalSupply = await test.totalSupply();
            let bal0 = await tk0.balanceOf(test.address);
            let bal1 = await tk1.balanceOf(test.address);
            let liq = await test.balanceOf(test.address);
            expect(balAddr1.div(5)).to.be.equal(liq);

            let amounts = await test.connect(addr1).callStatic["burn(address)"](addr1.address);
            let amount0 = amounts[1];
            let amount1 = amounts[0].mul(70).div(100);
            let computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            let kLast = await test.kLast();
            let totalSupply = await test.totalSupply();
            let liquidityDelta = kLast
                .sub(computedLiq)
                .mul(totalSupply)
                .div(kLast);
            expect(liquidityDelta).to.be.lt(liq);

            let balAddr1Before = await test.balanceOf(addr1.address);
            expect(balAddr1.sub(balAddr1.div(5))).to.be.equal(balAddr1Before);

            let bal0Addr1Before = await tk0.balanceOf(addr1.address);
            let bal1Addr1Before = await tk1.balanceOf(addr1.address);

            await test.connect(addr1).functions["burn(uint256,uint256,address)"](amount1, amount0, addr1.address);

            let balAddr1After = await test.balanceOf(addr1.address);
            let bal0Addr1After = await tk0.balanceOf(addr1.address);
            let bal1Addr1After = await tk1.balanceOf(addr1.address);

            expect(balAddr1After).to.be.equal(balAddr1Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr1After).to.be.equal(bal0Addr1Before.add(amount0));
            expect(bal1Addr1After).to.be.equal(bal1Addr1Before.add(amount1));

            let balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(3));

            bal0 = await tk0.balanceOf(test.address);
            bal1 = await tk1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);
            expect(balAddr2.div(3)).to.be.equal(liq);

            amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            //in case of liqidityDelta < liquidity, it works well even though token0 has more ratio.
            amount0 = amounts[1].mul(105).div(100);
            amount1 = amounts[0].mul(70).div(100);
            computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            kLast = await test.kLast();
            totalSupply = await test.totalSupply();
            liquidityDelta = kLast
                .sub(computedLiq)
                .mul(totalSupply)
                .div(kLast);
            expect(liquidityDelta).to.be.lt(liq);

            let balAddr2Before = await test.balanceOf(addr2.address);
            expect(balAddr2.sub(balAddr2.div(3))).to.be.equal(balAddr2Before);

            let bal0Addr2Before = await tk0.balanceOf(addr2.address);
            let bal1Addr2Before = await tk1.balanceOf(addr2.address);

            await test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address);

            let balAddr2After = await test.balanceOf(addr2.address);
            let bal0Addr2After = await tk0.balanceOf(addr2.address);
            let bal1Addr2After = await tk1.balanceOf(addr2.address);

            expect(balAddr2After).to.be.equal(balAddr2Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr2After).to.be.equal(bal0Addr2Before.add(amount0));
            expect(bal1Addr2After).to.be.equal(bal1Addr2Before.add(amount1));

            //in case of liqidityDelta < liquidity, it works well even though token1 has more ratio.
            balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(4));

            bal0 = await tk0.balanceOf(test.address);
            bal1 = await tk1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);
            expect(balAddr2.div(4)).to.be.equal(liq);

            amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            amount0 = amounts[1].mul(30).div(100);
            amount1 = amounts[0].mul(103).div(100);
            computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            kLast = await test.kLast();
            totalSupply = await test.totalSupply();
            liquidityDelta = kLast
                .sub(computedLiq)
                .mul(totalSupply)
                .div(kLast);
            expect(liquidityDelta).to.be.lt(liq);

            balAddr2Before = await test.balanceOf(addr2.address);
            expect(balAddr2.sub(balAddr2.div(4))).to.be.equal(balAddr2Before);

            bal0Addr2Before = await tk0.balanceOf(addr2.address);
            bal1Addr2Before = await tk1.balanceOf(addr2.address);

            await test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address);

            balAddr2After = await test.balanceOf(addr2.address);
            bal0Addr2After = await tk0.balanceOf(addr2.address);
            bal1Addr2After = await tk1.balanceOf(addr2.address);

            expect(balAddr2After).to.be.equal(balAddr2Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr2After).to.be.equal(bal0Addr2Before.add(amount0));
            expect(bal1Addr2After).to.be.equal(bal1Addr2Before.add(amount1));

            //in case of liqidityDelta < liquidity, it works well even though users want to receive token with 100% token0.
            balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(3));

            bal0 = await tk0.balanceOf(test.address);
            bal1 = await tk1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);
            expect(balAddr2.div(3)).to.be.equal(liq);

            amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            amount0 = amounts[1].mul(110).div(100);
            amount1 = 0;
            computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            kLast = await test.kLast();
            totalSupply = await test.totalSupply();
            liquidityDelta = kLast
                .sub(computedLiq)
                .mul(totalSupply)
                .div(kLast);
            expect(liquidityDelta).to.be.lt(liq);

            balAddr2Before = await test.balanceOf(addr2.address);
            expect(balAddr2.sub(balAddr2.div(3))).to.be.equal(balAddr2Before);

            bal0Addr2Before = await tk0.balanceOf(addr2.address);
            bal1Addr2Before = await tk1.balanceOf(addr2.address);

            await test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address);

            balAddr2After = await test.balanceOf(addr2.address);
            bal0Addr2After = await tk0.balanceOf(addr2.address);
            bal1Addr2After = await tk1.balanceOf(addr2.address);

            expect(balAddr2After).to.be.equal(balAddr2Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr2After).to.be.equal(bal0Addr2Before.add(amount0));
            expect(bal1Addr2After).to.be.equal(bal1Addr2Before.add(amount1));

            //in case of liqidityDelta < liquidity, it works well even though users want to receive token with 100% token1.
            balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.mul(2).div(3));

            bal0 = await tk0.balanceOf(test.address);
            bal1 = await tk1.balanceOf(test.address);
            liq = await test.balanceOf(test.address);
            expect(balAddr2.mul(2).div(3)).to.be.equal(liq);

            amounts = await test.connect(addr2).callStatic["burn(address)"](addr2.address);

            amount0 = 0;
            amount1 = amounts[0].mul(111).div(100);
            computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            kLast = await test.kLast();
            totalSupply = await test.totalSupply();
            liquidityDelta = kLast
                .sub(computedLiq)
                .mul(totalSupply)
                .div(kLast);
            expect(liquidityDelta).to.be.lt(liq);

            balAddr2Before = await test.balanceOf(addr2.address);
            expect(balAddr2.sub(balAddr2.mul(2).div(3))).to.be.equal(balAddr2Before);

            bal0Addr2Before = await tk0.balanceOf(addr2.address);
            bal1Addr2Before = await tk1.balanceOf(addr2.address);

            await test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address);

            balAddr2After = await test.balanceOf(addr2.address);
            bal0Addr2After = await tk0.balanceOf(addr2.address);
            bal1Addr2After = await tk1.balanceOf(addr2.address);

            expect(balAddr2After).to.be.equal(balAddr2Before.add(liq.sub(liquidityDelta)));
            expect(bal0Addr2After).to.be.equal(bal0Addr2Before.add(amount0));
            expect(bal1Addr2After).to.be.equal(bal1Addr2Before.add(amount1));
        });

        it("Should fail if both amount0, 1 are zero or users want to withdraw much more tokens they are eligible for withdrawing ", async function() {
            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr2.address);

            let balAddr2 = await test.balanceOf(addr2.address);
            await test.connect(addr2).transfer(test.address, balAddr2.div(3));

            let bal0 = await tk0.balanceOf(test.address);
            let bal1 = await tk1.balanceOf(test.address);
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

            let computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            let kLast = await test.kLast();
            let totalSupply = await test.totalSupply();
            let liquidityDelta = kLast
                .sub(computedLiq)
                .mul(totalSupply)
                .div(kLast);
            expect(liquidityDelta).to.be.gt(liq);

            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            //revert with much amount. token1 is much more.
            amount0 = amounts[1];
            amount1 = amounts[0].mul(120).div(100);

            computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            kLast = await test.kLast();
            totalSupply = await test.totalSupply();
            liquidityDelta = kLast
                .sub(computedLiq)
                .mul(totalSupply)
                .div(kLast);
            expect(liquidityDelta).to.be.gt(liq);

            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            //revert with much amount. token0 is zero and token1 is much more.
            amount0 = 0;
            amount1 = bal1.mul(9).div(10);

            computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            kLast = await test.kLast();
            liquidityDelta = kLast.sub(computedLiq);
            expect(liquidityDelta).to.be.gt(liq);

            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            //revert with much amount. token1 is zero and token0 is much more.
            amount0 = bal0.mul(9).div(10);
            amount1 = 0;

            computedLiq = await cmc.computeLiquidity(bal1.sub(amount1), bal0.sub(amount0), getData(20));
            kLast = await test.kLast();
            totalSupply = await test.totalSupply();
            liquidityDelta = kLast
                .sub(computedLiq)
                .mul(totalSupply)
                .div(kLast);
            expect(liquidityDelta).to.be.gt(liq);

            await expect(
                test.connect(addr2).functions["burn(uint256,uint256,address)"](amount1, amount0, addr2.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");
        });

        it("Should swap from one to the other well and emit event", async function() {
            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr1.address);

            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr1.address);

            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr1.address);

            await tk0.transfer(test.address, rand());
            await tk1.transfer(test.address, rand());
            await test.mint(addr2.address);

            await tk0.transfer(addr1.address, BigNumber.from(2).pow(112));
            await tk0.transfer(addr2.address, BigNumber.from(2).pow(112));
            await tk1.transfer(addr1.address, BigNumber.from(2).pow(112));
            await tk1.transfer(addr2.address, BigNumber.from(2).pow(112));

            let tk0bal = await tk0.balanceOf(test.address);
            let tk1bal = await tk1.balanceOf(test.address);

            let tk0aIn0 = rand();
            if (tk0aIn0.gt(tk0bal.div(2))) {
                while (tk0aIn0.gt(tk0bal.div(2))) {
                    tk0aIn0 = rand();
                }
            }
            let tk1aOut0 = await cmc.computeAmountOut(tk0aIn0, tk1bal, tk0bal, getData(20), 3, 1);
            let exTk1aOut0 = tk1aOut0 < 10 ** 6 ? tk1aOut0.add(10) : tk1aOut0.add(tk1aOut0.div(10 ** 6));

            await tk0.connect(addr1).transfer(test.address, tk0aIn0);
            await expect(
                test.functions["swap(uint256,uint256,address)"](exTk1aOut0, 0, addr1.address)
            ).to.be.revertedWith("MIRIN: LIQUIDITY");

            let tx = await test.connect(addr1).functions["swap(uint256,uint256,address)"](tk1aOut0, 0, addr1.address);
            let res = await tx.wait();
            const last = res.events.length - 1;

            expect(res.events[last].event).to.be.equal("Swap");
            expect(res.events[last].args[0]).to.be.equal(addr1.address);
            expect(res.events[last].args[1]).to.be.equal(0);
            expect(res.events[last].args[2]).to.be.equal(tk0aIn0);
            expect(res.events[last].args[3]).to.be.equal(tk1aOut0);
            expect(res.events[last].args[4]).to.be.equal(0);
            expect(res.events[last].args[5]).to.be.equal(addr1.address);

            tk0bal = await tk0.balanceOf(test.address);
            tk1bal = await tk1.balanceOf(test.address);

            let tk0aOut0 = rand();
            if (tk0aOut0.gt(tk0bal.div(2))) {
                while (tk0aOut0.gt(tk0bal.div(2))) {
                    tk0aOut0 = rand();
                }
            }
            let exTk0aOut0 = tk0aOut0 < 10 ** 6 ? tk0aOut0.add(10) : tk0aOut0.add(tk0aOut0.div(10 ** 6));

            let tk1aIn0 = await cmc.computeAmountIn(tk0aOut0, tk1bal, tk0bal, getData(20), 3, 0);

            await tk1.connect(addr1).transfer(test.address, tk1aIn0);
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
        });

        it("Should fail in several cases when swapping", async function() {
            //
        });
    });
    /*
    describe("Franchised Pool Test", function () {
        beforeEach(async function () {
            test = await getMP(tk0.address, tk1.address, cmc.address, getData(20), operator.address, 10, swapFeeTo.address);
        });
    });
*/
});

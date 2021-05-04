const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils } = require("ethers");
const { Decimal } = require("decimal.js");
Decimal18 = Decimal.clone({ precision: 18 });
Decimal40 = Decimal.clone({ precision: 40 });

let aIn, aOut, rIn, rOut, swapFee, wI, wO;

function randRA() {
    let i, j, dec;
    let RA = 0;
    dec = Math.floor(Math.random() * 28) + 6;
    for (i = 6; i <= dec; i++) {
        j = Math.floor(Math.random() * 10); //0~9
        if (i === 6 && j === 0) j = 1;
        if (i === 33 && j >= 5) j -= 5;
        RA = BigNumber.from(RA).add(BigNumber.from(10).pow(i).mul(j));
    }
    return RA;
}

function randRAforCL() {
    const Uint112Max = BigNumber.from(2).pow(112).sub(1);
    let i, j, dec;
    while (true) {
        let RA = 0;
        dec = Math.floor(Math.random() * 35);
        for (i = 0; i <= dec; i++) {
            j = Math.floor(Math.random() * 10); //0~9
            if (i === 0 && j === 0) j = 1;
            RA = BigNumber.from(RA).add(BigNumber.from(10).pow(i).mul(j));
        }
        if (Uint112Max.gte(RA)) {
            return RA;
        }
    }
}

function randParams() {
    wI = Math.floor(Math.random() * 99) + 1; //1~99
    wO = 100 - wI; //1~99
    swapFee = Math.floor(Math.random() * 101); //0~100

    rIn = randRA();
    rOut = randRA();
    aIn = randRA();
    aOut = randRA();
}

function randParamsforCL() {
    wI = Math.floor(Math.random() * 99) + 1; //1~99
    wO = 100 - wI; //1~99
    swapFee = Math.floor(Math.random() * 101); //0~100

    rIn = randRAforCL();
    rOut = randRAforCL();
    aIn = randRAforCL();
    aOut = randRAforCL();
}

function getData() {
    let d1 = BigNumber.from(wI).toHexString();
    return utils.hexZeroPad(d1, 32);
}

describe("MirinMath2 Test", function () {
    let CMC, test;
    let n, js, con, data;
    const BASE = BigNumber.from(10).pow(18);

    before(async function () {
        CMC = await ethers.getContractFactory("ConstantMeanCurve");
        test = await CMC.deploy();
    });

    it("Should fail if decodeData is not valid", async function () {
        wO = 0;
        wI = 100;
        data = getData();
        await expect(test.decodeData(data, 0)).to.be.revertedWith("MIRIN: INVALID_DATA");

        wO = 100;
        wI = 0;
        data = getData();
        await expect(test.decodeData(data, 0)).to.be.revertedWith("MIRIN: INVALID_DATA");
    });

    it("Should decode Data which is valid", async function () {
        n = 0;
        while (n < 100) {
            randParams();
            data = getData();
            con = await test.decodeData(data, 0);
            assert.isTrue(wI === con[0] && wO === con[1]);
            n++;
        }
    });

    it("Should fail in some cases in computeAmountOut function", async function () {
        randParams();
        aIn = 0;
        data = getData();
        await expect(test.computeAmountOut(aIn, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
            "MIRIN: INSUFFICIENT_INPUT_AMOUNT"
        );

        randParams();
        rIn = 0;
        data = getData();
        await expect(test.computeAmountOut(aIn, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
            "MIRIN: INSUFFICIENT_LIQUIDITY"
        );
        randParams();
        rOut = 0;
        data = getData();
        await expect(test.computeAmountOut(aIn, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
            "MIRIN: INSUFFICIENT_LIQUIDITY"
        );

        randParams();
        swapFee = 101;
        data = getData();
        await expect(test.computeAmountOut(aIn, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
            "MIRIN: INVALID_SWAP_FEE"
        );
    });

    it("Should work tokenIn is not 0 in computeAmountOut function", async function () {
        let Out1, Out2, r0, r1, tempW;
        n = 0;
        while (n < 10) {
            randParams();
            if (BigNumber.from(aIn).lte(rIn.div(2)) && BigNumber.from(aIn).lte(rOut.div(2))) {
                data = getData();
                r0 = rIn;
                r1 = rOut;

                Out1 = await test.computeAmountOut(aIn, r0, r1, data, swapFee, 0);

                tempW = wI;
                wI = wO;
                wO = tempW;

                data = getData();
                Out2 = await test.computeAmountOut(aIn, r1, r0, data, swapFee, 1);

                expect(Out1).to.be.eq(Out2);
                n++;
            }
        }
    });

    it("Should compute amoutOut value as precisely as possible", async function () {
        n = 0;
        while (n < 2000) {
            randParams();
            data = getData();
            if (BigNumber.from(aIn).gt(rIn.div(2))) {
                await expect(test.computeAmountOut(aIn, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
                    "MIRIN: ERR_MAX_IN_RATIO"
                );
            } else {
                Out = await test.computeAmountOut(aIn, rIn, rOut, data, swapFee, 0);
                let jsBase = Decimal18(rIn.toString()).div(rIn.add(aIn.mul(1000 - swapFee).div(1000)).toString());

                let jsPower = jsBase.pow(Decimal(wI).div(wO)).mul(BASE.toString()).floor();
                js = rOut.mul(BASE.sub(jsPower.toString())).div(BASE);
                let js1 = rOut
                    .mul(BASE.sub(jsPower.sub(2).toString()))
                    .div(BASE)
                    .add(2);
                let js2 = rOut
                    .mul(BASE.sub(jsPower.add(2).toString()))
                    .div(BASE)
                    .sub(2);

                if (js.isZero()) {
                    //about 20k times in 100k trials
                    if (!Out.isZero()) {
                        expect(Out).to.be.lte(js1); //about 0.5k in 100k
                    }
                } else if (jsBase.eq(1)) {
                    //never happen in 100k
                    expect(Out.toNumber()).to.be.eq(0);
                } else if (Math.floor((Math.abs(Out - js) / js) * 1000000) > 1) {
                    //about 10k in 100k
                    expect(Out).to.be.lte(js1);
                    expect(Out).to.be.gte(js2);
                } else {
                    expect(Math.floor((Math.abs(Out - js) / js) * 1000000)).to.be.lte(1); //about 70k in 100k
                }

                if (!js.isZero()) n++;
            }
        }
    });

    it("Should fail in some cases in computeAmountIn function", async function () {
        randParams();
        aOut = 0;
        data = getData();
        await expect(test.computeAmountIn(aOut, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
            "MIRIN: INSUFFICIENT_INPUT_AMOUNT"
        );

        randParams();
        rIn = 0;
        data = getData();
        await expect(test.computeAmountIn(aOut, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
            "MIRIN: INSUFFICIENT_LIQUIDITY"
        );
        randParams();
        rOut = 0;
        data = getData();
        await expect(test.computeAmountIn(aOut, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
            "MIRIN: INSUFFICIENT_LIQUIDITY"
        );

        randParams();
        swapFee = 101;
        data = getData();
        await expect(test.computeAmountIn(aOut, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
            "MIRIN: INVALID_SWAP_FEE"
        );
    });

    it("Should work tokenIn is not 0 in computeAmountIn function", async function () {
        let In1, In2, r0, r1, tempW;
        n = 0;
        while (n < 10) {
            randParams();
            if (BigNumber.from(aOut).lte(rIn.div(3)) && BigNumber.from(aOut).lte(rOut.div(3))) {
                data = getData();
                r0 = rIn;
                r1 = rOut;

                In1 = await test.computeAmountIn(aOut, r0, r1, data, swapFee, 0);

                tempW = wI;
                wI = wO;
                wO = tempW;

                data = getData();
                In2 = await test.computeAmountIn(aOut, r1, r0, data, swapFee, 1);

                expect(In1).to.be.eq(In2);
                n++;
            }
        }
    });

    it("Should compute amoutIn value as precisely as possible", async function () {
        n = 0;
        while (n < 2000) {
            randParams();
            data = getData();
            if (BigNumber.from(aOut).gt(BigNumber.from(rOut).div(3))) {
                await expect(test.computeAmountIn(aOut, rIn, rOut, data, swapFee, 0)).to.be.revertedWith(
                    "MIRIN: ERR_MAX_OUT_RATIO"
                );
            } else {
                In = await test.computeAmountIn(aOut, rIn, rOut, data, swapFee, 0);

                let jsBase = Decimal(rOut.toString())
                    .div(rOut.sub(aOut).toString())
                    .mul(BASE.toString())
                    .floor()
                    .div(BASE.toString());

                let jsPower = jsBase.pow(Decimal(wO).div(wI)).mul(BASE.toString()).floor();
                let jsPower1 = jsBase.add(Decimal("1e-18")).pow(Decimal(wO).div(wI)).mul(BASE.toString()).floor();
                let jsPower2 = jsBase.sub(Decimal("1e-18")).pow(Decimal(wO).div(wI)).mul(BASE.toString()).floor();
                js = rIn.mul(BigNumber.from(jsPower.toHex()).sub(BASE)).div(BASE.sub(BASE.mul(swapFee).div(1000)));
                let js1 = rIn
                    .mul(BigNumber.from(jsPower1.add(2).toHex()).sub(BASE))
                    .div(BASE.sub(BASE.mul(swapFee).div(1000)))
                    .add(2);
                let js2 = rIn
                    .mul(BigNumber.from(jsPower2.sub(2).toHex()).sub(BASE))
                    .div(BASE.sub(BASE.mul(swapFee).div(1000)))
                    .sub(2);

                if (js.isZero()) {
                    //about 23k times in 100k trials
                    if (!In.isZero()) {
                        //about 0.5k in 100k
                        expect(In).to.be.lte(js1);
                    }
                } else if (jsBase.eq(1)) {
                    //never happen in 100k
                    expect(In.toNumber()).to.be.eq(0);
                } else if (Math.floor((Math.abs(In - js) / js) * 1000000) > 1) {
                    //about 8k in 100k
                    expect(In).to.be.lte(js1);
                    expect(In).to.be.gte(js2);
                } else {
                    expect(Math.floor((Math.abs(In - js) / js) * 1000000)).to.be.lte(1); //about 70k in 100k
                }

                if (!js.isZero()) n++;
            }
        }
    });
});

describe("ConstantMeanCurve additional Test", function () {
    let CMC, test;
    let n, js, con, data;
    const BASE = BigNumber.from(10).pow(18);

    before(async function () {
        CMC = await ethers.getContractFactory("ConstantMeanCurve");
        test = await CMC.deploy();
    });

    it("Should return false whatever data is in canUpdateData fn", async function () {
        let p1 = utils.hexZeroPad(BigNumber.from(13579).toHexString(), 32);
        let p2 = utils.formatBytes32String("Hello, world!");

        expect(await test.canUpdateData(p1, p2)).to.be.false;
    });

    it("Should return false if data is not valid through isValidData fn", async function () {
        wO = 0;
        wI = 100;
        data = getData();
        expect(await test.isValidData(data)).to.be.false;

        wO = 100;
        wI = 0;
        data = getData();
        expect(await test.isValidData(data)).to.be.false;
    });

    it("Should pass true if data is valid through isValidData fn", async function () {
        n = 0;
        while (n < 100) {
            randParams();
            data = getData();
            expect(await test.isValidData(data)).to.be.true;
            n++;
        }
    });

    it("Should compute price as precisely as possible", async function () {
        let r0, r1, w0, w1;
        n = 0;
        while (n < 100) {
            randParams();
            data = getData();
            r0 = rIn;
            r1 = rOut;
            w0 = wI;
            w1 = wO;

            con = await test.computePrice(r0, r1, data, 0);
            js = r1.mul(BigNumber.from(2).pow(112)).mul(w0).div(r0).div(w1);
            expect(con).to.eq(js);
            n++;
        }
        n = 0;
        while (n < 100) {
            randParams();
            data = getData();
            r0 = rOut;
            r1 = rIn;
            w0 = wO;
            w1 = wI;

            con = await test.computePrice(r0, r1, data, 1);
            js = r0.mul(BigNumber.from(2).pow(112)).mul(w1).div(r1).div(w0);
            expect(con).to.eq(js);
            n++;
        }
    });

    it("Should compute Liquidity as precisely as possible", async function () {
        const Fixed1 = BigNumber.from(2).pow(127);
        let r0, r1, w0, w1;
        n = 0;

        while (n < 700) {
            randParamsforCL();
            r0 = rIn;
            r1 = rOut;
            w0 = wI;
            w1 = wO;
            data = getData();

            let lnLiq = Decimal40(r0.toHexString())
                .ln()
                .mul(w0)
                .add(Decimal40(r1.toHexString()).ln().mul(w1))
                .div(w0 + w1)
                .mul(Fixed1.toHexString())
                .floor();

            js = lnLiq.div(Fixed1.toHexString()).exp().floor();
            let js1 = js.mul(1 + Math.pow(10, -8)).floor();
            let js2 = js.mul(1 - Math.pow(10, -8)).floor();
            con = await test.computeLiquidity(r0, r1, data);

            if (con.gte(Math.pow(10, 10))) {
                expect(con).to.be.lte(BigNumber.from(js1.toHex()));
                expect(con).to.be.gte(BigNumber.from(js2.toHex()));
            } else {
                expect(con).to.be.lte(BigNumber.from(js1.add(10).toHex()));
                expect(con).to.be.gte(BigNumber.from(js2.sub(10).toHex()));
            }
            n++;
        }
    });
});

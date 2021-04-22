const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { Decimal } = require("decimal.js");
Decimal18 = Decimal.clone({ precision: 18 });

let aIn, aOut, rIn, rOut, swapFee, wI, wO;

function randRA() {
    let RA = 0,
        i,
        j,
        dec;
    dec = Math.floor(Math.random() * 28) + 6;
    for (i = 6; i <= dec; i++) {
        j = Math.floor(Math.random() * 10); //0~9
        if (i === 6 && j === 0) j = 1;
        if (i === 33 && j >= 5) j -= 5;
        RA = BigNumber.from(RA).add(BigNumber.from(10).pow(i).mul(j));
    }
    return RA;
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

function getData() {
    let d1 = BigNumber.from(2).pow(240).mul(wO).add(BigNumber.from(2).pow(248).mul(wI)).toHexString();
    if (ethers.utils.isHexString(d1, 32)) return d1;
    else return ethers.utils.hexZeroPad(d1, 32);
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
        let data;
        wO = 0;
        wI = 100;
        data = getData();
        await expect(test.decodeData(data, 0)).to.be.revertedWith("MIRIN: INVALID_DATA");

        wO = 100;
        wI = 0;
        data = getData();
        await expect(test.decodeData(data, 0)).to.be.revertedWith("MIRIN: INVALID_DATA");

        wO = 23;
        wI = 70;
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
        while (n < 1000) {
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
        while (n < 1000) {
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

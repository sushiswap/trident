const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = ethers;

describe("MirinMath Test_Former Part", function () {
    let test;

    const FIXED1 = BigNumber.from(2).pow(127);
    // const FIXED2 = BigNumber.from(2).pow(128);
    const FIXED3 = BigNumber.from(2).pow(97);
    const FIXED4 = BigNumber.from(2).pow(240);
    const FIXED5 = BigNumber.from(2).pow(113);
    const BASE = BigNumber.from(10).pow(8);

    async function deployTest() {
        const Test = await ethers.getContractFactory("MirinMathTestFormerPart");
        return await Test.deploy();
    }

    function getBASELog(x, y) {
        return Math.log(y) / Math.log(x);
    }

    before(async function () {
        test = await deployTest();
    });

    it("floorLog2", async function () {
        let i = 0;
        while (i < 10) {
            let j = Math.floor(Math.random() * 10) + 1;
            expect(await test._floorLog2(j)).to.be.equal(Math.floor(getBASELog(2, j)));
            j = Math.floor(Math.random() * 1000000000000000) + 1;
            expect(await test._floorLog2(j)).to.be.equal(Math.floor(getBASELog(2, j)));
            j = BigNumber.from(2)
                .pow(240)
                .mul(Math.floor(Math.random() * 10) + 1);
            expect(await test._floorLog2(j)).to.be.equal(Math.floor(getBASELog(2, j)));
            i++;
        }
    });

    it("ln", async function () {
        let i = 0,
            j,
            k,
            con,
            js;
        while (i < 10) {
            j = Math.floor(Math.random() * Math.pow(2, 10)) + 1; //(1 ~ 2^10)
            k = FIXED1.mul(j); //(1 ~ 2^10) * 2^127
            con = BigNumber.from(await test._ln(k))
                .div(FIXED3)
                .toNumber();
            js = Math.log(j) * Math.pow(2, 30);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));

            j = Math.floor(Math.random() * Math.pow(2, 15)) + 1; //(1 ~ 2^15)
            k = FIXED4.mul(j); //(2^113 ~ 2^128) * 2^127
            con = BigNumber.from(await test._ln(k))
                .div(FIXED3)
                .toNumber();
            js = Math.log(FIXED5.mul(j)) * Math.pow(2, 30);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));
            i++;
        }
        j = Math.floor(1.3 * Math.pow(2, 30)); //1.3 * 2^30
        k = FIXED3.mul(j); //1.3 * 2^127
        con = BigNumber.from(await test._ln(k))
            .div(FIXED3)
            .toNumber();
        js = Math.log(1.3) * Math.pow(2, 30);
        assert.isTrue((Math.abs(con - js) / con) * Math.pow(10, 6) < 1);

        j = Math.floor(0.7 * Math.pow(2, 30)); //0.7 * 2^30
        k = FIXED3.mul(j); //0.7 * 2^127
        con = BigNumber.from(await test._ln(k));
        assert.isTrue(con.isZero());
    });

    it("generalLog", async function () {
        let i = 0,
            j,
            k,
            con,
            js;
        while (i < 10) {
            j = Math.floor(Math.random() * Math.pow(2, 10)) + 1; //(1 ~ 2^10)
            k = FIXED1.mul(j); //(1 ~ 2^10) * 2^127
            con = BigNumber.from(await test._generalLog(k))
                .div(FIXED3)
                .toNumber();
            js = getBASELog(10, j) * Math.pow(2, 30);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6)); //difference lower than 1ppm

            j = Math.floor(Math.random() * Math.pow(2, 15)) + 1; //(1 ~ 2^15)
            k = FIXED4.mul(j); //(2^113 ~ 2^128) * 2^127
            con = BigNumber.from(await test._generalLog(k))
                .div(FIXED3)
                .toNumber();
            js = getBASELog(10, FIXED5.mul(j)) * Math.pow(2, 30);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));
            i++;
        }
        j = Math.floor(1.3 * Math.pow(2, 30)); //1.3 * 2^30
        k = FIXED3.mul(j); //1.3 * 2^127
        con = BigNumber.from(await test._generalLog(k))
            .div(FIXED3)
            .toNumber();
        js = getBASELog(10, 1.3) * Math.pow(2, 30);
        assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));

        j = Math.floor(0.7 * Math.pow(2, 30)); //0.7 * 2^30
        k = FIXED3.mul(j); //0.7 * 2^127
        con = BigNumber.from(await test._generalLog(k));
        assert.isTrue(con.isZero());
    });

    it("optimalLog", async function () {
        await expect(test._optimalLog(FIXED1.sub(1))).to.be.revertedWith("MIRIN: OVERFLOW");
        await expect(test._optimalLog(FIXED4)).to.be.reverted;
        let i = 0,
            j,
            k,
            con,
            js;
        while (i < 10) {
            j = Math.floor((Math.random() * (Math.exp(1) - 1) + 1) * BASE);
            k = FIXED1.mul(j).div(BASE);
            con = BigNumber.from(await test._optimalLog(k))
                .mul(BASE)
                .div(FIXED1)
                .toNumber();
            js = Math.floor(Math.log(k / FIXED1) * BASE);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));
            i++;
        }
    });

    it("optimalExp", async function () {
        let i = 0,
            j,
            k,
            con,
            js;
        while (i < 10) {
            j = Math.ceil(Math.random() * Math.pow(2, 30)); //(0.xxx ~ 1.000) * 2^30
            k = FIXED3.mul(j); //(0.xxx ~ 1.000) * 2^127
            con = BigNumber.from(await test._optimalExp(k))
                .div(FIXED1)
                .toNumber();
            js = Math.floor(Math.exp(j / Math.pow(2, 30)));
            assert.isTrue(con === js);

            j = Math.floor(Math.random() * 16 * Math.pow(2, 30)); //(0.xxx ~ 15.xxx) * 2^30
            k = FIXED3.mul(j); //(0.xxx ~ 15.xxx) * 2^127
            con = BigNumber.from(await test._optimalExp(k))
                .div(FIXED1)
                .toNumber();
            js = Math.floor(Math.exp(j / Math.pow(2, 30)));
            assert.isTrue(con === js);
            i++;
        }
        await expect(test._optimalExp(BigNumber.from("0x800000000000000000000000000000000"))).to.be.revertedWith(
            "MIRIN: OVERFLOW"
        );
    });
});

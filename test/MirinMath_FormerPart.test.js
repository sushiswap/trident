const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

describe("MirinMath Test_Former Part", function () {
    let Test, test;
    let i = 0;
    let j, k, con, js, temp;

    const Fixed1 = BigNumber.from(2).pow(127);
    // const Fixed2 = BigNumber.from(2).pow(128);
    const Fixed3 = BigNumber.from(2).pow(97);
    const Fixed4 = BigNumber.from(2).pow(240);
    const Fixed5 = BigNumber.from(2).pow(113);
    const Base = BigNumber.from(10).pow(8);

    function getBaseLog(x, y) {
        return Math.log(y) / Math.log(x);
    }

    before(async function () {
        Test = await ethers.getContractFactory("MirinMathTestFormerPart");
        test = await Test.deploy();
    });

    it("floorLog2", async function () {
        while (i < 10) {
            j = Math.floor(Math.random() * 10) + 1;
            expect(await test._floorLog2(j)).to.be.equal(Math.floor(getBaseLog(2, j)));
            j = Math.floor(Math.random() * 1000000000000000) + 1;
            expect(await test._floorLog2(j)).to.be.equal(Math.floor(getBaseLog(2, j)));
            j = BigNumber.from(2)
                .pow(240)
                .mul(Math.floor(Math.random() * 10) + 1);
            expect(await test._floorLog2(j)).to.be.equal(Math.floor(getBaseLog(2, j)));
            i++;
        }
    });

    it("ln", async function () {
        i = 0;
        while (i < 10) {
            j = Math.floor(Math.random() * Math.pow(2, 10)) + 1; //(1 ~ 2^10)
            k = Fixed1.mul(j); //(1 ~ 2^10) * 2^127
            con = BigNumber.from(await test._ln(k))
                .div(Fixed3)
                .toNumber();
            js = Math.log(j) * Math.pow(2, 30);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));

            j = Math.floor(Math.random() * Math.pow(2, 15)) + 1; //(1 ~ 2^15)
            k = Fixed4.mul(j); //(2^113 ~ 2^128) * 2^127
            con = BigNumber.from(await test._ln(k))
                .div(Fixed3)
                .toNumber();
            js = Math.log(Fixed5.mul(j)) * Math.pow(2, 30);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));
            i++;
        }
        j = Math.floor(1.3 * Math.pow(2, 30)); //1.3 * 2^30
        k = Fixed3.mul(j); //1.3 * 2^127
        con = BigNumber.from(await test._ln(k))
            .div(Fixed3)
            .toNumber();
        js = Math.log(1.3) * Math.pow(2, 30);
        assert.isTrue((Math.abs(con - js) / con) * Math.pow(10, 6) < 1);

        j = Math.floor(0.7 * Math.pow(2, 30)); //0.7 * 2^30
        k = Fixed3.mul(j); //0.7 * 2^127
        con = BigNumber.from(await test._ln(k));
        assert.isTrue(con.isZero());
    });

    it("generalLog", async function () {
        i = 0;
        while (i < 10) {
            j = Math.floor(Math.random() * Math.pow(2, 10)) + 1; //(1 ~ 2^10)
            k = Fixed1.mul(j); //(1 ~ 2^10) * 2^127
            con = BigNumber.from(await test._generalLog(k))
                .div(Fixed3)
                .toNumber();
            js = getBaseLog(10, j) * Math.pow(2, 30);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6)); //difference lower than 1ppm

            j = Math.floor(Math.random() * Math.pow(2, 15)) + 1; //(1 ~ 2^15)
            k = Fixed4.mul(j); //(2^113 ~ 2^128) * 2^127
            con = BigNumber.from(await test._generalLog(k))
                .div(Fixed3)
                .toNumber();
            js = getBaseLog(10, Fixed5.mul(j)) * Math.pow(2, 30);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));
            i++;
        }
        j = Math.floor(1.3 * Math.pow(2, 30)); //1.3 * 2^30
        k = Fixed3.mul(j); //1.3 * 2^127
        con = BigNumber.from(await test._generalLog(k))
            .div(Fixed3)
            .toNumber();
        js = getBaseLog(10, 1.3) * Math.pow(2, 30);
        assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));

        j = Math.floor(0.7 * Math.pow(2, 30)); //0.7 * 2^30
        k = Fixed3.mul(j); //0.7 * 2^127
        con = BigNumber.from(await test._generalLog(k));
        assert.isTrue(con.isZero());
    });

    it("optimalLog", async function () {
        await expect(test._optimalLog(Fixed1.sub(1))).to.be.revertedWith("MIRIN: OVERFLOW");
        await expect(test._optimalLog(Fixed4)).to.be.reverted;
        i = 0;
        while (i < 10) {
            j = Math.floor((Math.random() * (Math.exp(1) - 1) + 1) * Base);
            k = Fixed1.mul(j).div(Base);
            con = BigNumber.from(await test._optimalLog(k))
                .mul(Base)
                .div(Fixed1)
                .toNumber();
            js = Math.floor(Math.log(k / Fixed1) * Base);
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));
            i++;
        }
    });

    it("optimalExp", async function () {
        i = 0;
        while (i < 10) {
            j = Math.ceil(Math.random() * Math.pow(2, 30)); //(0.xxx ~ 1.000) * 2^30
            k = Fixed3.mul(j); //(0.xxx ~ 1.000) * 2^127
            con = BigNumber.from(await test._optimalExp(k))
                .div(Fixed1)
                .toNumber();
            js = Math.floor(Math.exp(j / Math.pow(2, 30)));
            assert.isTrue(con === js);

            j = Math.floor(Math.random() * 16 * Math.pow(2, 30)); //(0.xxx ~ 15.xxx) * 2^30
            k = Fixed3.mul(j); //(0.xxx ~ 15.xxx) * 2^127
            con = BigNumber.from(await test._optimalExp(k))
                .div(Fixed1)
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

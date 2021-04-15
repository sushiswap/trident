const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

describe("MirinMath Test", function () {
    let Test, test;
    let i = 0;
    let j, k, con, js, temp;
    
    const Fixed1 = BigNumber.from(2).pow(127);
    const Fixed2 = BigNumber.from(2).pow(128);
    const Fixed3 = BigNumber.from(2).pow(97);
    const Fixed4 = BigNumber.from(2).pow(240);
    const Fixed5 = BigNumber.from(2).pow(113);
    const Base = BigNumber.from(10).pow(8);
    
    function getBaseLog(x, y) {
        return Math.log(y) / Math.log(x);
    }

    before(async function () {
        Test = await ethers.getContractFactory("MirinMathTest");
        test = await Test.deploy();
    });

    it("initialize, findPositionInMaxExpArray", async function () {
        con = await test._findPositionInMaxExpArray(0);
        expect(con).to.be.equal(127);
        await expect(test._findPositionInMaxExpArray(1)).to.be.reverted;
        
        await test._initialize();
        expect(await test._findPositionInMaxExpArray(1)).to.be.equal(127);
        
        temp = BigNumber.from("0x0292c5bdd3b92ec810287b1b3fffffffff").sub(100); //maxExpArray[89] = 0x0292c5bdd3b92ec810287b1b3fffffffff
        expect(await test._findPositionInMaxExpArray(temp)).to.be.equal(89);

        temp = BigNumber.from("0x075af62cbac95f7dfa7fffffffffffffff"); //maxExpArray[64] = 0x075af62cbac95f7dfa7fffffffffffffff
        expect(await test._findPositionInMaxExpArray(temp)).to.be.equal(64);

        temp = BigNumber.from("0x1c35fedd14ffffffffffffffffffffffff").add(1); //maxExpArray[32] = 0x1c35fedd14ffffffffffffffffffffffff
        await expect(test._findPositionInMaxExpArray(temp)).to.be.reverted;
    });

    it("max, min", async function () {
        expect(await test._max(10, 28)).to.be.equal(28);
        expect(await test._max(1896, 71)).to.be.equal(1896);
        expect(await test._min(9, 3)).to.be.equal(3);
        expect(await test._min(28216, 975161)).to.be.equal(28216);
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

    //generalEXP        TODO

    it("optimalLog", async function () {
        await expect(test._optimalLog(Fixed1.sub(1))).to.be.revertedWith("MIRIN: Outranged");
        await expect(test._optimalLog(Fixed4)).to.be.reverted;
        i = 0;
        while(i < 10) {
            j = Math.floor(((Math.random() * (Math.exp(1) - 1)) + 1) * Base);
            k = Fixed1.mul(j).div(Base);
            con = BigNumber.from(await test._optimalLog(k)).mul(Base).div(Fixed1).toNumber();
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
        await expect(test._optimalExp(BigNumber.from("0x800000000000000000000000000000000"))).to.be.revertedWith("MIRIN: Outranged");
    });

    //power            TODO

    it("sqrt", async function () {
        i = 0;
        while (i < 10) {
            j = Math.random() * 50;
            k = Math.floor(Math.pow(2, j));
            con = BigNumber.from(await test._sqrt(k)).toNumber();
            js = Math.floor(Math.sqrt(k));
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));

            j = Math.floor(Math.random() * 10000) + 1;
            k = Fixed4.mul(j).div(10000);
            con = BigNumber.from(await test._sqrt(k))
                .div(Fixed3)
                .toNumber();
            js = Math.floor(Math.sqrt(k)) / Fixed3;
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));
            i++;
        }
        expect(await test._sqrt(3)).to.be.equal(1);
        expect(await test._sqrt(2)).to.be.equal(1);
        expect(await test._sqrt(1)).to.be.equal(1);
        expect(await test._sqrt(0)).to.be.equal(0);
    });

    it("stddev", async function () {
        function jsStd(arr) {
            let mean = Math.floor(arr.reduce((sum, current) => sum + current, 0) / arr.length);
            let vol = arr.reduce((sum, current) => sum + Math.pow(current - mean, 2), 0) / (arr.length - 1);
            let std = Math.sqrt(Math.floor(vol));
            return std;
        }

        function rdInt(a, b) {
            return Math.ceil(Math.random() * Math.pow(2, a) * b);
        }

        function rdArr() {
            let n = Math.ceil(Math.random() * 10) + 2;
            let arr = [];
            for (i = 0; i < n; i++) {
                arr.push(rdInt(Math.ceil(Math.random() * 40), Math.ceil(Math.random() * 500)));
            }
            return arr;
        }

        i = 0;
        while (i < 10) {
            temp = rdArr();
            con = BigNumber.from(await test._stddev(temp)).toNumber();
            js = Math.floor(jsStd(temp));
            expect((con - js) / con).to.be.below(Math.pow(10, -6));
            i++;
        }
    });

    it("ncdf", async function () {
        con = BigNumber.from(await test._ncdf(Fixed1)).toNumber();
        assert.isTrue(Math.floor(con / Math.pow(10, 10)) - 0.8413 * 10000 <= 1);
        con = BigNumber.from(await test._ncdf(Fixed2)).toNumber();
        assert.isTrue(Math.floor(con / Math.pow(10, 10)) - 0.9772 * 10000 <= 1);
        temp = Fixed1.mul(18).div(100);
        con = BigNumber.from(await test._ncdf(temp)).toNumber();
        assert.isTrue(Math.floor(con / Math.pow(10, 10)) - 0.5714 * 10000 <= 1);
        con = BigNumber.from(await test._ncdf(0)).toNumber();
        assert.isTrue(Math.floor(con / Math.pow(10, 10)) - 0.5 * 10000 <= 1);
    });

    it("vol", async function () {
        function jsVol(arr) {
            let _v = 0;
            for (i = 1; i < arr.length; i++) {
                if (arr[i - 1] > arr[i]) {
                    _v += Math.pow(getBaseLog(10, arr[i - 1] / arr[i]), 2);
                } else {
                    _v += Math.pow(getBaseLog(10, arr[i] / arr[i - 1]), 2);
                }
            }
            let vol = Math.sqrt(252 * Math.sqrt(_v / (arr.length - 1)));
            return vol;
        }

        async function checkVol(arr) {
            con = BigNumber.from(await test._vol(arr))
                .div(Math.pow(10, 8))
                .toNumber();
            js = BigNumber.from(Math.floor(jsVol(arr) * Math.pow(10, 10))).toNumber();
            assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));
        }

        await checkVol([1, 2, 4, 8, 16]);
        await checkVol([8, 3, 1, 6, 4]);
        await checkVol([9, 8, 6, 3, 2]);
        await checkVol([5, 19, 88, 44, 150]);
    });

    it("C, quoteOptionAll", async function () {
        //C
        const Q = BigNumber.from(10).pow(18);

        function sqrt(value) {
            x = BigNumber.from(value);
            let z = x.add(1).div(2);
            let y = x;
            while (z.sub(y).isNegative()) {
                y = z;
                z = x.div(z).add(z).div(2);
            }
            return y;
        }

        async function jsC(t, v, sp, st) {
            let d1, d2;
            if (BigNumber.from(sp).eq(BigNumber.from(st))) {
                return BigNumber.from(3988425491)
                    .mul(sp)
                    .div(Math.pow(10, 10))
                    .mul(v)
                    .div(Q)
                    .mul(sqrt(Q.mul(t).div(365)))
                    .div(Math.pow(10, 9));
            }
            const sigma = BigNumber.from(v).pow(2).div(2);
            const sigmaB = BigNumber.from(10).pow(36);

            const sig = Q.mul(sigma).div(sigmaB).mul(t).div(365);
            const sSQRT = BigNumber.from(v)
                .mul(sqrt(Q.mul(t).div(365)))
                .div(Math.pow(10, 9));

            d1 = Q.mul(BigNumber.from(Math.floor(Math.log(sp / st) * Math.pow(10, 6)))).div(Math.pow(10, 6));
            d1 = d1.add(sig).mul(Q).div(sSQRT);
            d2 = d1.sub(sSQRT);

            const cdfD1 = Math.floor(await test._ncdf(Fixed1.mul(d1).div(Q)));
            const cdfD2 = Math.floor(await test._ncdf(Fixed1.mul(d2).div(Q)));
            js = BigNumber.from(sp)
                .mul(cdfD1)
                .div(BigNumber.from(10).pow(14))
                .sub(st.mul(cdfD2).div(BigNumber.from(10).pow(14)));

            return js;
        }

        let t = BigNumber.from(3000);
        let v = BigNumber.from(10).pow(12).mul(4);
        let sp = BigNumber.from(10).pow(19).mul(5);
        let st = BigNumber.from(10).pow(19).mul(5);

        con = await test._C(t, v, sp, st);
        js = await jsC(t, v, sp, st);
        assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));

        t = BigNumber.from(350000);
        v = BigNumber.from(10).pow(15).mul(2);
        sp = BigNumber.from(10).pow(20).mul(8);
        st = BigNumber.from(10).pow(20).mul(7);

        con = await test._C(t, v, sp, st);
        js = await jsC(t, v, sp, st);
        assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));

        t = BigNumber.from(362800);
        v = BigNumber.from(10).pow(16).mul(7);
        sp = BigNumber.from(10).pow(22).mul(3);
        st = BigNumber.from(10).pow(20).mul(7);

        con = await test._C(t, v, sp, st);
        js = await jsC(t, v, sp, st);
        assert.isTrue(Math.abs(con - js) / con < Math.pow(10, -6));

        //quoteOptionAll
        t = BigNumber.from(5000);
        v = BigNumber.from(10).pow(13).mul(2);
        sp = BigNumber.from(10).pow(22).mul(2);
        st = BigNumber.from(10).pow(22).mul(2);

        con = await test._quoteOptionAll(t, v, sp, st);
        let js_c = await jsC(t, v, sp, st);
        let js_p = js_c;
        assert.isTrue(Math.abs(con[0] - js_c) / con[0] < Math.pow(10, -6));
        assert.isTrue(Math.abs(con[1] - js_p) / con[1] < Math.pow(10, -6));

        t = BigNumber.from(350000);
        v = BigNumber.from(10).pow(15).mul(2);
        sp = BigNumber.from(10).pow(20).mul(8);
        st = BigNumber.from(10).pow(20).mul(7);

        con = await test._quoteOptionAll(t, v, sp, st);
        js_c = await jsC(t, v, sp, st);
        js_p = sp.sub(st).add(js_c);
        assert.isTrue(Math.abs(con[0] - js_c) / con[0] < Math.pow(10, -6));
        assert.isTrue(Math.abs(con[1] - js_p) / con[1] < Math.pow(10, -6));

        t = BigNumber.from(362800);
        v = BigNumber.from(10).pow(16).mul(7);
        sp = BigNumber.from(10).pow(20).mul(7);
        st = BigNumber.from(10).pow(22).mul(3);

        con = await test._quoteOptionAll(t, v, sp, st);
        js_p = await jsC(t, v, st, sp);
        js_c = st.sub(sp).add(js_p);
        assert.isTrue(Math.abs(con[0] - js_c) / con[0] < Math.pow(10, -6));
        assert.isTrue(Math.abs(con[1] - js_p) / con[1] < Math.pow(10, -6));
    });
});

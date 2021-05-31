// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

library MirinMath {
    uint256 internal constant ONE = 1;
    uint256 internal constant FIXED_1 = 0x080000000000000000000000000000000;
    uint256 internal constant FIXED_2 = 0x100000000000000000000000000000000;
    uint256 internal constant SQRT_1 = 13043817825332782212;
    uint256 internal constant LNX = 3988425491;
    uint256 internal constant LOG_10_2 = 3010299957;
    uint256 internal constant LOG_E_2 = 6931471806;
    uint256 internal constant BASE10 = 1e10;

    uint256 internal constant MAX_NUM = 0x200000000000000000000000000000000;
    uint8 internal constant MIN_PRECISION = 32;
    uint8 internal constant MAX_PRECISION = 127;
    uint256 internal constant OPT_LOG_MAX_VAL = 0x15bf0a8b1457695355fb8ac404e7a79e3;
    uint256 internal constant OPT_EXP_MAX_VAL = 0x800000000000000000000000000000000;

    uint256 internal constant BASE18 = 1e18;
    uint256 internal constant MIN_POWER_BASE = 1 wei;
    uint256 internal constant MAX_POWER_BASE = (2 * BASE18) - 1 wei;
    uint256 internal constant POWER_PRECISION = BASE18 / 1e10;

    // computes square roots using the babylonian method
    // https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method
    // credit for this implementation goes to
    // https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol#L687
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        // this block is equivalent to r = uint256(1) << (BitMath.mostSignificantBit(x) / 2);
        // however that code costs significantly more gas
        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }

    function ln(uint256 x) internal pure returns (uint256) {
        uint256 res = 0;

        // If x >= 2, then we compute the integer part of log2(x), which is larger than 0.
        if (x >= FIXED_2) {
            uint8 count = floorLog2(x / FIXED_1);
            x >>= count; // now x < 2
            res = count * FIXED_1;
        }

        // If x > 1, then we compute the fraction part of log2(x), which is larger than 0.
        if (x > FIXED_1) {
            for (uint8 i = MAX_PRECISION; i > 0; --i) {
                x = (x * x) / FIXED_1; // now 1 < x < 4
                if (x >= FIXED_2) {
                    x >>= 1; // now 1 < x < 2
                    res += ONE << (i - 1);
                }
            }
        }

        return (res * LOG_E_2) / BASE10;
    }

    /**
     * @dev computes log(x / FIXED_1) * FIXED_1.
     * This functions assumes that "x >= FIXED_1", because the output would be negative otherwise.
     */
    function generalLog(uint256 x) internal pure returns (uint256) {
        uint256 res = 0;

        // If x >= 2, then we compute the integer part of log2(x), which is larger than 0.
        if (x >= FIXED_2) {
            uint8 count = floorLog2(x / FIXED_1);
            x >>= count; // now x < 2
            res = count * FIXED_1;
        }

        // If x > 1, then we compute the fraction part of log2(x), which is larger than 0.
        if (x > FIXED_1) {
            for (uint8 i = MAX_PRECISION; i > 0; --i) {
                x = (x * x) / FIXED_1; // now 1 < x < 4
                if (x >= FIXED_2) {
                    x >>= 1; // now 1 < x < 2
                    res += ONE << (i - 1);
                }
            }
        }

        return (res * LOG_10_2) / BASE10;
    }

    /**
     * @dev computes the largest integer smaller than or equal to the binary logarithm of the input.
     */
    function floorLog2(uint256 _n) internal pure returns (uint8) {
        uint8 res = 0;

        if (_n < 256) {
            // At most 8 iterations
            while (_n > 1) {
                _n >>= 1;
                res += 1;
            }
        } else {
            // Exactly 8 iterations
            for (uint8 s = 128; s > 0; s >>= 1) {
                if (_n >= (ONE << s)) {
                    _n >>= s;
                    res |= s;
                }
            }
        }

        return res;
    }

    /**
     * @dev computes ln(x / FIXED_1) * FIXED_1
     * Input range: FIXED_1 <= x <= OPT_LOG_MAX_VAL - 1
     * Auto-generated via 'PrintFunctionOptimalLog.py'
     * Detailed description:
     * - Rewrite the input as a product of natural exponents and a single residual r, such that 1 < r < 2
     * - The natural logarithm of each (pre-calculated) exponent is the degree of the exponent
     * - The natural logarithm of r is calculated via Taylor series for log(1 + x), where x = r - 1
     * - The natural logarithm of the input is calculated by summing up the intermediate results above
     * - For example: log(250) = log(e^4 * e^1 * e^0.5 * 1.021692859) = 4 + 1 + 0.5 + log(1 + 0.021692859)
     */
    function optimalLog(uint256 x) internal pure returns (uint256) {
        require(FIXED_1 <= x, "MIRIN: OVERFLOW");
        uint256 res = 0;

        uint256 y;
        uint256 z;
        uint256 w;

        if (x >= 0xd3094c70f034de4b96ff7d5b6f99fcd8) {
            res += 0x40000000000000000000000000000000;
            x = (x * FIXED_1) / 0xd3094c70f034de4b96ff7d5b6f99fcd8;
        } // add 1 / 2^1
        if (x >= 0xa45af1e1f40c333b3de1db4dd55f29a7) {
            res += 0x20000000000000000000000000000000;
            x = (x * FIXED_1) / 0xa45af1e1f40c333b3de1db4dd55f29a7;
        } // add 1 / 2^2
        if (x >= 0x910b022db7ae67ce76b441c27035c6a1) {
            res += 0x10000000000000000000000000000000;
            x = (x * FIXED_1) / 0x910b022db7ae67ce76b441c27035c6a1;
        } // add 1 / 2^3
        if (x >= 0x88415abbe9a76bead8d00cf112e4d4a8) {
            res += 0x08000000000000000000000000000000;
            x = (x * FIXED_1) / 0x88415abbe9a76bead8d00cf112e4d4a8;
        } // add 1 / 2^4
        if (x >= 0x84102b00893f64c705e841d5d4064bd3) {
            res += 0x04000000000000000000000000000000;
            x = (x * FIXED_1) / 0x84102b00893f64c705e841d5d4064bd3;
        } // add 1 / 2^5
        if (x >= 0x8204055aaef1c8bd5c3259f4822735a2) {
            res += 0x02000000000000000000000000000000;
            x = (x * FIXED_1) / 0x8204055aaef1c8bd5c3259f4822735a2;
        } // add 1 / 2^6
        if (x >= 0x810100ab00222d861931c15e39b44e99) {
            res += 0x01000000000000000000000000000000;
            x = (x * FIXED_1) / 0x810100ab00222d861931c15e39b44e99;
        } // add 1 / 2^7
        if (x >= 0x808040155aabbbe9451521693554f733) {
            res += 0x00800000000000000000000000000000;
            x = (x * FIXED_1) / 0x808040155aabbbe9451521693554f733;
        } // add 1 / 2^8

        z = y = x - FIXED_1;
        w = (y * y) / FIXED_1;
        res += (z * (0x100000000000000000000000000000000 - y)) / 0x100000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^01 / 01 - y^02 / 02
        res += (z * (0x0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa - y)) / 0x200000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^03 / 03 - y^04 / 04
        res += (z * (0x099999999999999999999999999999999 - y)) / 0x300000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^05 / 05 - y^06 / 06
        res += (z * (0x092492492492492492492492492492492 - y)) / 0x400000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^07 / 07 - y^08 / 08
        res += (z * (0x08e38e38e38e38e38e38e38e38e38e38e - y)) / 0x500000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^09 / 09 - y^10 / 10
        res += (z * (0x08ba2e8ba2e8ba2e8ba2e8ba2e8ba2e8b - y)) / 0x600000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^11 / 11 - y^12 / 12
        res += (z * (0x089d89d89d89d89d89d89d89d89d89d89 - y)) / 0x700000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^13 / 13 - y^14 / 14
        res += (z * (0x088888888888888888888888888888888 - y)) / 0x800000000000000000000000000000000; // add y^15 / 15 - y^16 / 16

        return res;
    }

    /**
     * @dev computes e ^ (x / FIXED_1) * FIXED_1
     * input range: 0 <= x <= OPT_EXP_MAX_VAL - 1
     * auto-generated via 'PrintFunctionOptimalExp.py'
     * Detailed description:
     * - Rewrite the input as a sum of binary exponents and a single residual r, as small as possible
     * - The exponentiation of each binary exponent is given (pre-calculated)
     * - The exponentiation of r is calculated via Taylor series for e^x, where x = r
     * - The exponentiation of the input is calculated by multiplying the intermediate results above
     * - For example: e^5.521692859 = e^(4 + 1 + 0.5 + 0.021692859) = e^4 * e^1 * e^0.5 * e^0.021692859
     */
    function optimalExp(uint256 x) internal pure returns (uint256) {
        require(x <= OPT_EXP_MAX_VAL - 1, "MIRIN: OVERFLOW");
        uint256 res = 0;

        uint256 y;
        uint256 z;

        z = y = x % 0x10000000000000000000000000000000; // get the input modulo 2^(-3)
        z = (z * y) / FIXED_1;
        res += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
        z = (z * y) / FIXED_1;
        res += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
        z = (z * y) / FIXED_1;
        res += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
        z = (z * y) / FIXED_1;
        res += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
        z = (z * y) / FIXED_1;
        res += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
        z = (z * y) / FIXED_1;
        res += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
        z = (z * y) / FIXED_1;
        res += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
        z = (z * y) / FIXED_1;
        res += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
        z = (z * y) / FIXED_1;
        res += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
        z = (z * y) / FIXED_1;
        res += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
        z = (z * y) / FIXED_1;
        res += z * 0x000000000001c638; // add y^16 * (20! / 16!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
        z = (z * y) / FIXED_1;
        res += z * 0x000000000000017c; // add y^18 * (20! / 18!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000000000014; // add y^19 * (20! / 19!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000000000001; // add y^20 * (20! / 20!)
        res = res / 0x21c3677c82b40000 + y + FIXED_1; // divide by 20! and then add y^1 / 1! + y^0 / 0!

        if ((x & 0x010000000000000000000000000000000) != 0)
            res = (res * 0x1c3d6a24ed82218787d624d3e5eba95f9) / 0x18ebef9eac820ae8682b9793ac6d1e776; // multiply by e^2^(-3)
        if ((x & 0x020000000000000000000000000000000) != 0)
            res = (res * 0x18ebef9eac820ae8682b9793ac6d1e778) / 0x1368b2fc6f9609fe7aceb46aa619baed4; // multiply by e^2^(-2)
        if ((x & 0x040000000000000000000000000000000) != 0)
            res = (res * 0x1368b2fc6f9609fe7aceb46aa619baed5) / 0x0bc5ab1b16779be3575bd8f0520a9f21f; // multiply by e^2^(-1)
        if ((x & 0x080000000000000000000000000000000) != 0)
            res = (res * 0x0bc5ab1b16779be3575bd8f0520a9f21e) / 0x0454aaa8efe072e7f6ddbab84b40a55c9; // multiply by e^2^(+0)
        if ((x & 0x100000000000000000000000000000000) != 0)
            res = (res * 0x0454aaa8efe072e7f6ddbab84b40a55c5) / 0x00960aadc109e7a3bf4578099615711ea; // multiply by e^2^(+1)
        if ((x & 0x200000000000000000000000000000000) != 0)
            res = (res * 0x00960aadc109e7a3bf4578099615711d7) / 0x0002bf84208204f5977f9a8cf01fdce3d; // multiply by e^2^(+2)
        if ((x & 0x400000000000000000000000000000000) != 0)
            res = (res * 0x0002bf84208204f5977f9a8cf01fdc307) / 0x0000003c6ab775dd0b95b4cbee7e65d11; // multiply by e^2^(+3)

        return res;
    }

    function toInt(uint256 a) internal pure returns (uint256) {
        return a / BASE18;
    }

    function toFloor(uint256 a) internal pure returns (uint256) {
        return toInt(a) * BASE18;
    }

    function roundMul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * b;
        uint256 c1 = c0 + (BASE18 / 2);
        return c1 / BASE18;
    }

    function roundDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * BASE18;
        uint256 c1 = c0 + (b / 2);
        return c1 / b;
    }

    function ceilMul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * b;
        return c0 % BASE18 == 0 ? c0 / BASE18 : c0 / BASE18 + 1;
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * BASE18;
        return c0 % b == 0 ? c0 / b : c0 / b + 1;
    }

    function power(
        uint256 base,
        uint256 exp,
        bool isUp
    ) internal pure returns (uint256) {
        require(base >= MIN_POWER_BASE, "MIRIN: POWER_BASE_TOO_LOW");
        require(base <= MAX_POWER_BASE, "MIRIN: POWER_BASE_TOO_HIGH");

        uint256 whole = toFloor(exp);
        uint256 remain = exp - whole;
        uint256 wholePow;
        if (whole == 0) wholePow = BASE18;
        else if (whole == BASE18) wholePow = base;
        else wholePow = powInt(base, toInt(whole));

        if (remain == 0) {
            return wholePow;
        }
        uint256 partialResult = powFrac(base, remain, POWER_PRECISION, isUp);
        return ceilMul(wholePow, partialResult);
    }

    function powInt(uint256 a, uint256 n) private pure returns (uint256) {
        uint256 z = n % 2 != 0 ? a : BASE18;
        for (n /= 2; n > 1; n /= 2) {
            a = roundMul(a, a);

            if (n % 2 != 0) {
                z = roundMul(z, a);
            }
        }
        a = ceilMul(a, a);
        return ceilMul(z, a);
    }

    function powFrac(
        uint256 base,
        uint256 exp,
        uint256 precision,
        bool isUp
    ) private pure returns (uint256) {
        uint256 a = exp;
        (uint256 x, bool xneg) = base >= BASE18 ? (base - BASE18, false) : (BASE18 - base, true);
        uint256 term = BASE18;
        uint256 sum = term;
        bool negative = false;

        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * BASE18;
            (uint256 c, bool cneg) = a + BASE18 >= bigK ? (a + BASE18 - bigK, false) : (bigK - a - BASE18, true);
            term = roundMul(term, roundMul(c, x));
            term = roundDiv(term, bigK);
            if (term == 0) break;

            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = sum - term;
            } else {
                sum = sum + term;
            }
        }
        if (isUp && negative) sum = sum + term / 10;
        return sum;
    }
}

interface IMirinCurve {
    function canUpdateData(bytes32 oldData, bytes32 newData) external pure returns (bool);

    function isValidData(bytes32 data) external view returns (bool);

    function computeLiquidity(
        uint256 reserve0,
        uint256 reserve1,
        bytes32 data
    ) external view returns (uint256);

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external view returns (uint224);

    function computeAmountOut(
        uint256 amountIn,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view returns (uint256);

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view returns (uint256);
}

/**
 * @dev Constant mean curve for tokens with different possible weights (k = r_0^w_0 * r_1^w1)
 * @author LevX
 */
contract ConstantMeanCurve is IMirinCurve {
    uint8 public constant MAX_SWAP_FEE = 100;
    uint8 public constant WEIGHT_SUM = 100;
    uint8 private constant PRECISION = 104;

    function canUpdateData(bytes32, bytes32) public pure override returns (bool) {
        return false;
    }

    function isValidData(bytes32 data) public pure override returns (bool) {
        uint8 weight0 = uint8(uint256(data));
        uint8 weight1 = WEIGHT_SUM - weight0;
        return weight0 > 0 && weight1 > 0;
    }

    function decodeData(bytes32 data, uint8 tokenIn) public pure returns (uint8 weightIn, uint8 weightOut) {
        uint8 weight0 = uint8(uint256(data));
        uint8 weight1 = WEIGHT_SUM - weight0;
        require(weight0 > 0 && weight1 > 0, "MIRIN: INVALID_DATA");
        weightIn = tokenIn == 0 ? weight0 : weight1;
        weightOut = tokenIn == 0 ? weight1 : weight0;
    }

    function computeLiquidity(
        uint256 reserve0,
        uint256 reserve1,
        bytes32 data
    ) public pure override returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        uint256 maxVal = MirinMath.OPT_EXP_MAX_VAL - 1;
        uint256 lnR0 = MirinMath.ln(reserve0 * MirinMath.FIXED_1);
        uint256 lnR1 = MirinMath.ln(reserve1 * MirinMath.FIXED_1);
        uint256 lnLiq = (lnR0 * weight0 + lnR1 * weight1) / (weight0 + weight1);
        uint8 loop = uint8(lnLiq / maxVal);
        uint256 res = lnLiq % maxVal; //lnLiq = maxVal * loop + res

        uint256 liq = MirinMath.optimalExp(res);

        if (loop > 0) {
            uint256 maxValLiq = MirinMath.optimalExp(maxVal);
            uint256 limit = type(uint256).max / maxValLiq;
            for (uint8 i = 0; i < loop; i++) {
                uint256 t = liq / limit;
                liq = liq - (limit * t); //liqIni = limit * t + liqRes
                liq = ((limit * maxValLiq) / MirinMath.FIXED_1) * t + ((liq * maxValLiq) / MirinMath.FIXED_1);
            }
        }
        return liq / MirinMath.FIXED_1;
    }

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) public pure override returns (uint224) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return
            tokenIn == 0
                ? ((uint224(reserve1) * weight0) << PRECISION) / reserve0 / weight1
                : ((uint224(reserve0) * weight1) << PRECISION) / reserve1 / weight0;
    }

    function computeAmountOut(
        uint256 amountIn,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) public pure override returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        require(amountIn <= reserveIn / 2, "MIRIN: ERR_MAX_IN_RATIO");

        uint256 weightRatio = MirinMath.roundDiv(uint256(weightIn), uint256(weightOut));
        uint256 adjustedIn = amountIn * (MirinMath.BASE18 - (uint256(swapFee) * 10**15));
        uint256 base =
            MirinMath.ceilDiv(
                uint256(reserveIn) * MirinMath.BASE18,
                uint256(reserveIn) * MirinMath.BASE18 + adjustedIn
            );
        if (base == MirinMath.BASE18) {
            base = MirinMath.roundDiv(
                uint256(reserveIn) * MirinMath.BASE18,
                uint256(reserveIn) * MirinMath.BASE18 + adjustedIn
            );
        }
        uint256 pow = MirinMath.power(base, weightRatio, false);
        amountOut = (uint256(reserveOut) * (MirinMath.BASE18 - pow)) / MirinMath.BASE18;
    }

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) public pure override returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        require(amountOut <= reserveOut / 3, "MIRIN: ERR_MAX_OUT_RATIO");

        uint256 weightRatio = MirinMath.roundDiv(uint256(weightOut), uint256(weightIn));
        uint256 base = MirinMath.ceilDiv(uint256(reserveOut), uint256(reserveOut) - amountOut);
        uint256 pow = MirinMath.power(base, weightRatio, true);
        uint256 adjustedIn = uint256(reserveIn) * (pow - MirinMath.BASE18);
        uint256 denominator = (MirinMath.BASE18 - (uint256(swapFee) * 10**15));
        amountIn = adjustedIn % denominator == 0 ? adjustedIn / denominator : adjustedIn / denominator + 1;
    }
}

/**
 * @dev Originally DeriswapV1ERC20
 * @author Andre Cronje, LevX
 */
contract MirinERC20 {
    string public constant name = "Mirin";
    string public constant symbol = "MIRIN";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public immutable DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply + value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] = balanceOf[from] - value;
        totalSupply = totalSupply - value;
        emit Transfer(from, address(0), value);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        balanceOf[from] = balanceOf[from] - value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(from, to, value);
    }

    function _transferFrom(
        address from,
        address to,
        uint256 value
    ) internal {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] = allowance[from][msg.sender] - value;
        }
        _transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        _transferFrom(from, to, value);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
                )
            );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "MIRIN: INVALID_SIGNATURE");
        _approve(owner, spender, value);
    }
}

interface IERC20 {} interface IBentoBoxV1 {
    function balanceOf(IERC20, address) external view returns (uint256);

    function deposit(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);

    function withdraw(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);

    function transfer(
        IERC20 token,
        address from,
        address to,
        uint256 share
    ) external;

    function transferMultiple(
        IERC20 token,
        address from,
        address[] calldata tos,
        uint256[] calldata shares
    ) external;
}

interface IMirinCallee {
    function mirinCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract MirinPool is ConstantMeanCurve, MirinERC20 { // WIP - adapted for BentoBox vault & multiAMM deployer integration - see base template: https://github.com/sushiswap/mirin/blob/master/contracts/pool/MirinPool.sol *TO-DO: abstract curve library
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    IBentoBoxV1 private immutable bentoBox;

    uint8 public swapFee;
    uint8 public constant MIN_SWAP_FEE = 1;
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;

    address public masterFeeTo; // WIP - empty placeholder for testing - this addr will be stored in deployer / router?
    address public swapFeeTo;

    IERC20 public token0;
    IERC20 public token1;

    bytes32 public curveData;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "MIRIN: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier ensureDeadline(uint256 deadline) {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        _;
    }

    constructor(
        IBentoBoxV1 _bentoBox,
        IERC20 tokenA,
        IERC20 tokenB,
        bytes32 _curveData,
        uint8 _swapFee,
        address _swapFeeTo
    ) {
        (IERC20 _token0, IERC20 _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(address(_token0) != address(0), "MIRIN: ZERO_ADDRESS");
        require(_token0 != _token1, "MIRIN: IDENTICAL_ADDRESSES");
        require(isValidData(_curveData), "MIRIN: INVALID_CURVE_DATA");
        require(_swapFee >= MIN_SWAP_FEE && _swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        bentoBox = _bentoBox;
        token0 = _token0;
        token1 = _token1;
        curveData = _curveData;
        swapFee = _swapFee;
        swapFeeTo = _swapFeeTo;
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "MIRIN: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        if (blockTimestamp != _blockTimestampLast && _reserve0 != 0 && _reserve1 != 0) {
            bytes32 _curveData = curveData;
            unchecked {
                uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
                uint256 price0 = computePrice(_reserve0, _reserve1, _curveData, 0);
                price0CumulativeLast += price0 * timeElapsed;
                uint256 price1 = ConstantMeanCurve.computePrice(_reserve0, _reserve1, _curveData, 1);
                price1CumulativeLast += price1 * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;

        emit Sync(uint112(balance0), uint112(balance1));
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (uint256 computed) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            bytes32 _curveData = curveData;
            computed = ConstantMeanCurve.computeLiquidity(_reserve0, _reserve1, _curveData);
            if (computed > _kLast) {
                uint256 numerator = totalSupply * (computed - _kLast);
                uint256 denominator = (computed * (swapFee * 2 - 1)) + _kLast; // 0.05% of increased liquidity
                uint256 liquidity = numerator / denominator;
                if (liquidity > 0) {
                    if (swapFeeTo == address(0)) {
                        _mint(masterFeeTo, liquidity * 2);
                    } else {
                        _mint(masterFeeTo, liquidity);
                        _mint(swapFeeTo, liquidity);
                    }
                }
            }
        }
    }

    function addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensureDeadline(deadline) returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        if (_reserve0 == 0 && _reserve1 == 0) {
            (amount0, amount1) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal  = amountADesired * (_reserve1 / _reserve0);
            if (amountBOptimal  <= amountBDesired) {
                require(amountBOptimal  >= amountBMin, "MIRIN: INSUFFICIENT_B_AMOUNT");
                (amount0, amount1) = (amountADesired, amountBOptimal );
            } else {
                uint256 amountAOptimal = amountBDesired * (_reserve1 / _reserve0);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "MIRIN: INSUFFICIENT_A_AMOUNT");
                (amount0, amount1) = (amountAOptimal, amountBDesired);
            }
        }
        bentoBox.transfer(token0, msg.sender, address(this), amount0);
        bentoBox.transfer(token1, msg.sender, address(this), amount1);
        liquidity = mint(to);
    }

    function mint(address to) public lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        uint256 balance0 = bentoBox.balanceOf(token0, address(this));
        uint256 balance1 = bentoBox.balanceOf(token1, address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        bytes32 _curveData = curveData;
        uint256 computed = ConstantMeanCurve.computeLiquidity(uint112(balance0), uint112(balance1), _curveData);
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 k = ConstantMeanCurve.computeLiquidity(uint112(_reserve0), uint112(_reserve1), _curveData);
            liquidity = ((computed - k) * _totalSupply) / k;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function removeLiquidity(
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensureDeadline(deadline) returns (uint256 amountA, uint256 amountB) {
        this.transferFrom(msg.sender, address(this), liquidity); // send liquidity to this pool
        (amountA, amountB) = burn(to);
        require(amountA >= amountAMin, "MIRIN: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "MIRIN: INSUFFICIENT_B_AMOUNT");
    }

    function burn(address to) public lock returns (uint256 amount0, uint256 amount1) {
        IERC20 _token0 = IERC20(token0);                                 // gas savings
        IERC20 _token1 = IERC20(token1);                                 // gas savings
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        _mintFee(_reserve0, _reserve1);
        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance(_token0, _token1);
        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        bentoBox.transfer(_token0, address(this), to, amount0);
        bentoBox.transfer(_token1, address(this), to, amount1);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = ConstantMeanCurve.computeLiquidity(balance0, balance1, curveData);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function burn(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external lock {
        require(amount0 > 0 || amount1 > 0, "MIRIN: INVALID_AMOUNTS");

        uint256 liquidity = balanceOf[address(this)];

        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        _mintFee(_reserve0, _reserve1);

        bytes32 _curveData = curveData;
        uint256 k = ConstantMeanCurve.computeLiquidity(_reserve0, _reserve1, _curveData);
        uint256 computed =
            ConstantMeanCurve.computeLiquidity(_reserve0 - amount0, _reserve1 - amount1, _curveData);
        uint256 liquidityDelta = ((k - computed) * totalSupply) / k;

        require(liquidityDelta <= liquidity, "MIRIN: LIQUIDITY");
        if (liquidityDelta < liquidity) {
            _transfer(address(this), to, liquidity - liquidityDelta);
            liquidity = liquidityDelta;
        }

        _burn(address(this), liquidity);
        (uint256 balance0, uint256 balance1) = _balance(token0, token1);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function _balance(IERC20 _token0, IERC20 _token1) private view returns (uint256 balance0, uint256 balance1) {
        balance0 = bentoBox.balanceOf(_token0, address(this));
        balance1 = bentoBox.balanceOf(_token1, address(this));
    }

    function _compute(
        uint256 amount0In,
        uint256 amount1In,
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private view {
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * swapFee;
        bytes32 _curveData = curveData;
        require(
            ConstantMeanCurve.computeLiquidity(balance0Adjusted, balance1Adjusted, _curveData) >=
            ConstantMeanCurve.computeLiquidity(_reserve0 * 1000, _reserve1 * 1000, _curveData),
            "MIRIN: LIQUIDITY"
        );
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) private pure returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _transferCall(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data,
        IERC20 _token0,
        IERC20 _token1
    ) private {
        if (amount0Out > 0) bentoBox.transfer(_token0, address(this), to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) bentoBox.transfer(_token1, address(this), to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0Out, amount1Out, data);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) public lock {
        require(amount0Out > 0 || amount1Out > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "MIRIN: INSUFFICIENT_LIQUIDITY");
        { // scope for _token{0,1} avoids stack too deep errors
        IERC20 _token0 = token0; // gas savings
        IERC20 _token1 = token1; // gas savings
        require(to != address(_token0) && to != address(_token1), "MIRIN: INVALID_TO");
        _transferCall(amount0Out, amount1Out, to, data, _token0, _token1);
        }
        (uint256 balance0, uint256 balance1) = _balance(token0, token1);
        uint256 amount0In = balance0 + amount0Out - _reserve0;
        uint256 amount1In = balance1 + amount1Out - _reserve1;
        _compute(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        //emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to); WIP - Can this event be in deployer/router to avoid 'stack size too deep' error?
    }

    function swap( // WIP - formatted for {IPool}
        address tokenIn,
        address,
        bytes calldata context,
        address recipient,
        bool,
        uint256 amount
    ) external lock returns (uint256 oppositeSideAmount) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        if (IERC20(tokenIn) == token0) {
            oppositeSideAmount = _getAmountOut(amount, _reserve0, _reserve1);
            swap(0, oppositeSideAmount, recipient, context);
        } else {
            oppositeSideAmount = _getAmountOut(amount, _reserve1, _reserve0);
            swap(oppositeSideAmount, 0, recipient, context);
        }
    }

    function sync() external lock {
        _update(
            bentoBox.balanceOf(token0, address(this)),
            bentoBox.balanceOf(token1, address(this)),
            reserve0,
            reserve1,
            blockTimestampLast
        );
    }
}

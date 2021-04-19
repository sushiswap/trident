// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

library MirinMath2 {
    // TODO Checklist.
    // uint256 public constant MIN_WEIGHT = BASE;
    // uint256 public constant MAX_WEIGHT = BASE * 50;
    // uint256 public constant MAX_TOTAL_WEIGHT = BASE * 50;
    // uint256 public constant MIN_BALANCE = BASE / 10**12;
    // uint256 public constant MAX_IN_RATIO = BASE / 2;
    // uint256 public constant MAX_OUT_RATIO = (BASE / 3) + 1 wei;

    uint256 public constant BASE = 10**18;
    uint256 public constant MIN_POWER_BASE = 1 wei;
    uint256 public constant MAX_POWER_BASE = (2 * BASE) - 1 wei;
    uint256 public constant POWER_PRECISION = BASE / 10**10;


    function toInt(uint256 a) internal pure returns (uint256) {
        return a / BASE;
    }

    function toFloor(uint256 a) internal pure returns (uint256) {
        return toInt(a) * BASE;
    }

    function roundMul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * b;
        uint256 c1 = c0 + (BASE / 2);
        return c1 / BASE;
    }

    function roundDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * BASE;
        uint256 c1 = c0 + (b / 2);
        return c1 / b;
    }

    function power(uint256 base, uint256 exp) internal pure returns (uint256)
    {
        require(base >= MIN_POWER_BASE, "ERR_POWER_BASE_TOO_LOW");
        require(base <= MAX_POWER_BASE, "ERR_POWER_BASE_TOO_HIGH");

        uint256 whole  = toFloor(exp);   
        uint256 remain = exp - whole;

        uint256 wholePow = powInt(base, toInt(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint256 partialResult = powFrac(base, remain, POWER_PRECISION);
        return roundMul(wholePow, partialResult);
    }

    function powInt(uint256 a, uint256 n) private pure returns (uint256)
    {
        uint256 z = n % 2 != 0 ? a : BASE;

        for (n /= 2; n != 0; n /= 2) {
            a = roundMul(a, a);

            if (n % 2 != 0) {
                z = roundMul(z, a);
            }
        }
        return z;
    }

    function powFrac(uint256 base, uint256 exp, uint256 precision) private pure returns (uint256)
    {
        uint256 a = exp;
        (uint256 x, bool xneg)  = base >= BASE ? (base - BASE, false) : (BASE - base, true);
        uint256 term = BASE;
        uint256 sum = term;
        bool negative = false;

        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * BASE;
            (uint256 c, bool cneg) = a + BASE >= bigK ? (a + BASE - bigK, false) : (bigK - a - BASE, true);
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
        return sum;
    }     
}
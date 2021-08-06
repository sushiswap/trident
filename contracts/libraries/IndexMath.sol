// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Constants and math for Trident exchange index pools adapted from BalancerV1 `BMath`.
contract IndexMath {
    uint256 public constant BONE              = 10**18;
    uint256 public constant MIN_BOUND_TOKENS  = 2;
    uint256 public constant MAX_BOUND_TOKENS  = 8;
    uint256 public constant MIN_WEIGHT        = BONE;
    uint256 public constant MAX_WEIGHT        = BONE * 50;
    uint256 public constant MAX_TOTAL_WEIGHT  = BONE * 50;
    uint256 public constant MIN_BALANCE       = BONE / 10**12;
    uint256 public constant INIT_POOL_SUPPLY  = BONE * 100;
    uint256 public constant MIN_BPOW_BASE     = 1 wei;
    uint256 public constant MAX_BPOW_BASE     = (2 * BONE) - 1 wei;
    uint256 public constant BPOW_PRECISION    = BONE / 10**10;
    uint256 public constant MAX_IN_RATIO      = BONE / 2;
    uint256 public constant MAX_OUT_RATIO     = (BONE / 3) + 1 wei;
    
    function bsubSign(uint256 a, uint256 b)
        internal pure
        returns (uint256, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }
    
    function btoi(uint256 a)
        internal pure 
        returns (uint256)
    {
        return a / BONE;
    }

    function bfloor(uint256 a)
        internal pure
        returns (uint256)
    {
        return btoi(a) * BONE;
    }

    // DSMath.wpow
    function bpowi(uint256 a, uint256 n)
        internal pure
        returns (uint256)
    {
        uint256 z = n % 2 != 0 ? a : BONE;
        for (n /= 2; n != 0; n /= 2) {
            a = a * a;
            if (n % 2 != 0) {
                z = z * a;
            }
        }
        return z;
    }

    // Compute b^(e.w) by splitting it into (b^e)*(b^0.w).
    // Use `bpowi` for `b^e` and `bpowK` for k iterations
    // of approximation of b^0.w
    function bpow(uint256 base, uint256 exp)
        internal pure
        returns (uint256)
    {
        require(base >= MIN_BPOW_BASE, "ERR_BPOW_BASE_TOO_LOW");
        require(base <= MAX_BPOW_BASE, "ERR_BPOW_BASE_TOO_HIGH");

        uint256 whole  = bfloor(exp);   
        uint256 remain = exp - whole;

        uint256 wholePow = bpowi(base, btoi(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint256 partialResult = bpowApprox(base, remain, BPOW_PRECISION);
        return wholePow * partialResult;
    }

    function bpowApprox(uint256 base, uint256 exp, uint256 precision)
        internal pure
        returns (uint256)
    {
        // term 0:
        uint256 a     = exp;
        (uint x, bool xneg)  = bsubSign(base, BONE);
        uint256 term = BONE;
        uint256 sum   = term;
        bool negative = false;

        // term(k) = numer / denom 
        //         = (product(a - i - 1, i=1-->k) * x^k) / (k!)
        // each iteration, multiply previous term by (a-(k-1)) * x / k
        // continue until term is less than precision
        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * BONE;
            (uint256 c, bool cneg) = bsubSign(a, bigK - BONE);
            term = term * (c * x);
            term = term / bigK;
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

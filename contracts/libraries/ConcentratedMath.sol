// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

library ConcentratedMath {
    function log_2(uint256 x) internal pure returns (uint256) {
        unchecked {
            require (x > 0);
            uint256 msb = 0;
            uint256 xc = x;
            if (xc >= 0x10000000000000000) { xc >>= 64; msb += 64; }
            if (xc >= 0x100000000) { xc >>= 32; msb += 32; }
            if (xc >= 0x10000) { xc >>= 16; msb += 16; }
            if (xc >= 0x100) { xc >>= 8; msb += 8; }
            if (xc >= 0x10) { xc >>= 4; msb += 4; }
            if (xc >= 0x4) { xc >>= 2; msb += 2; }
            if (xc >= 0x2) msb += 1;  // No need to shift xc anymore

            uint256 result = msb - 64 << 64;
            uint256 ux = uint256 (uint256 (x)) << uint256 (127 - msb);
            for (uint256 bit = 0x8000000000000000; bit > 0; bit >>= 1) {
                ux *= ux;
                uint256 b = ux >> 255;
                ux >>= 127 + b;
                result += bit * uint256 (b);
            }
            return uint256 (result);
        }
    }

    function ln(uint256 x) internal pure returns (uint256) {
        unchecked {
            require (x > 0);
            return (log_2 (x) * 0xB17217F7D1CF79ABC9E3B39803F2F6AF >> 128);
        }
    }
    
    function pow(uint256 a, uint256 b) internal pure returns (uint256) { 
        return a**b;
    }
    
    function calcTick(uint256 rp) internal pure returns (uint256) {
        return ln(rp) * 2 / ln(10001);
    }
    
    function calcSqrtPrice(uint256 i) internal pure returns (uint256) {
        return pow(10001, i / 2);
    }
}

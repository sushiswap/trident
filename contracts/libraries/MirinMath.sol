// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

library MirinMath {
    /// @notice Adapted from https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol
    /// Copyright © 2019 by ABDK Consulting
    /// License-Identifier: BSD-4-Clause
    /// @dev Calculate sqrt (x) rounding down, where x is unsigned 256-bit integer number
    ///  @param x unsigned 256-bit integer number
    /// @return unsigned 256-bit integer number
    function sqrt(uint256 x) internal pure returns (uint256) {
        unchecked {
            if (x == 0) return 0;
            else {
                uint256 xx = x;
                uint256 r = 1;
                if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
                if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
                if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
                if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
                if (xx >= 0x100) { xx >>= 8; r <<= 4; }
                if (xx >= 0x10) { xx >>= 4; r <<= 2; }
                if (xx >= 0x8) { r <<= 1; }
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1; // Seven iterations should be enough
                uint256 r1 = x / r;
                return r < r1 ? r : r1;
            }
        }
    }
}

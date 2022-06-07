// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

library StablePoolMath {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
}

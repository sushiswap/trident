// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "../libraries/MirinMath.sol";

contract MirinMathTest {
    function _floorLog2(uint256 _n) public pure returns (uint8) {
        return MirinMath.floorLog2(_n);
    }

    function _ln(uint256 x) public pure returns (uint256) {
        return MirinMath.ln(x);
    }

    function _generalLog(uint256 x) public pure returns (uint256) {
        return MirinMath.generalLog(x);
    }

    function _optimalLog(uint256 x) public pure returns (uint256) {
        return MirinMath.optimalLog(x);
    }

    function _optimalExp(uint256 x) public pure returns (uint256) {
        return MirinMath.optimalExp(x);
    }
}

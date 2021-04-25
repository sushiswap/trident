// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../libraries/MirinMath.sol";

contract MirinMathTest {
    function _max(uint256 a, uint256 b) public pure returns (uint256) {
        return MirinMath.max(a, b);
    }

    function _min(uint256 x, uint256 y) public pure returns (uint256) {
        return MirinMath.min(x, y);
    }

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

    function _sqrt(uint256 y) public pure returns (uint256 z) {
        return MirinMath.sqrt(y);
    }

    function _stddev(uint256[] memory numbers) public pure returns (uint256) {
        return MirinMath.stddev(numbers);
    }

    function _ncdf(uint256 x) public pure returns (uint256) {
        return MirinMath.ncdf(x);
    }

    function _vol(uint256[] memory p) public pure returns (uint256) {
        return MirinMath.vol(p);
    }

    function _quoteOptionAll(
        uint256 t,
        uint256 v,
        uint256 sp,
        uint256 st
    ) public pure returns (uint256 call, uint256 put) {
        return MirinMath.quoteOptionAll(t, v, sp, st);
    }

    function _C(
        uint256 t,
        uint256 v,
        uint256 sp,
        uint256 st
    ) public pure returns (uint256) {
        return MirinMath.C(t, v, sp, st);
    }
}

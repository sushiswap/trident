// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../MirinMath.sol";

contract MirinMathTest is MirinMath {
    function _initialize() public {
        return initialize();
    }

    function _findPositionInMaxExpArray(uint256 _x) public view returns (uint8) {
        return findPositionInMaxExpArray(_x);
    }

    function _max(uint256 a, uint256 b) public pure returns (uint256) {
        return max(a, b);
    }

    function _min(uint256 x, uint256 y) public pure returns (uint256) {
        return min(x, y);
    }

    function _floorLog2(uint256 _n) public pure returns (uint8) {
        return floorLog2(_n);
    }

    function _ln(uint256 x) public pure returns (uint256) {
        return ln(x);
    }

    function _generalLog(uint256 x) public pure returns (uint256) {
        return generalLog(x);
    }

    function _generalExp(uint256 _x, uint8 _precision) public pure returns (uint256) {
        return generalExp(_x, _precision);
    }

    function _optimalLog(uint256 x) public pure returns (uint256) {
        return optimalLog(x);
    }

    function _optimalExp(uint256 x) public pure returns (uint256) {
        return optimalExp(x);
    }

    function _power(uint256 _baseN, uint256 _baseD, uint32 _expN, uint32 _expD) public view returns (uint256, uint8) {
        return power(_baseN, _baseD, _expN, _expD);
    }

    function _sqrt(uint256 y) public pure returns (uint256 z) {
        return sqrt(y);
    }

    function _stddev(uint256[] memory numbers) public pure returns (uint256) {
        return stddev(numbers);
    }

    function _ncdf(uint256 x) public pure returns (uint256) {
        return ncdf(x);
    }

    function _vol(uint256[] memory p) public pure returns (uint256) {
        return vol(p);
    }

    function _quoteOptionAll(
        uint256 t,
        uint256 v,
        uint256 sp,
        uint256 st
    ) public pure returns (uint256 call, uint256 put) {
        return quoteOptionAll(t, v, sp, st);
    }

    function _C(
        uint256 t,
        uint256 v,
        uint256 sp,
        uint256 st
    ) public pure returns (uint256) {
        return C(t, v, sp, st);
    }
}

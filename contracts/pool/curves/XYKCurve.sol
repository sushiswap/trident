// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../../interfaces/IMirinCurve.sol";

/**
 * @dev Curve with x∗y=k market making.
 */
contract XYKCurve is IMirinCurve {
    uint224 private constant Q112 = 2**112;
    
    function encode(uint112 y) private pure returns (uint224 z) {
        unchecked {z = uint224(y) * Q112;} // never overflows
    }

    function uqdiv(uint224 x, uint112 y) private pure returns (uint224 z) {
        z = x / uint224(y);
    }
    
    function canUpdateData(bytes32, bytes32) public pure override returns (bool) {
        return false;
    }

    function isValidData(bytes32 data) public pure override returns (bool) {
        return uint256(data) == 0;
    }

    function computeLiquidity(
        uint256 reserve0,
        uint256 reserve1,
        bytes32
    ) public pure override returns (uint256) {
        return reserve0 * reserve1;
    }

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32,
        uint8
    ) public pure override returns (uint224) {
        return uqdiv(encode(reserve1), reserve0);
    }
    
    function computeAmountOut(
        uint256,
        uint112,
        uint112,
        bytes32,
        uint8,
        uint8
    ) public pure override returns (uint256) {
        revert("MIRIN: NOT_IMPLEMENTED");
    }

    function computeAmountIn(
        uint256,
        uint112,
        uint112,
        bytes32,
        uint8,
        uint8
    ) public pure override returns (uint256) {
        revert("MIRIN: NOT_IMPLEMENTED");
    }
}

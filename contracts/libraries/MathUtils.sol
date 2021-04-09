// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./SafeMath.sol";

/**
 * @title MathUtils library
 * @notice A library to be used in conjuction with SafeMath. Contains functions for calculating
 * differences between two uint256.
 *
 * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/MathUtils.sol
 */
library MathUtils {
    using SafeMath for uint256;

    /**
     * @notice Compares a and b and returns true if the difference between a and b
     *         is less than 1 or equal to each other.
     * @param a uint256 to compare with
     * @param b uint256 to compare with
     * @return True if the difference between a and b is less than 1 or equal,
     *         otherwise return false
     */
    function within1(uint256 a, uint256 b) internal pure returns (bool) {
        return (difference(a, b) <= 1);
    }

    /**
     * @notice Calculates absolute difference between a and b
     * @param a uint256 to compare with
     * @param b uint256 to compare with
     * @return Difference between a and b
     */
    function difference(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > b) {
            return a.sub(b);
        }
        return b.sub(a);
    }
}

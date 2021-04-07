// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

// This doesn't have receive payable function.
contract C1 {
    uint256 public total;

    function increase(uint256 amount) public {
        total += amount;
    }

    function fail(uint256 a) public pure returns (uint256 b) {
        assert(a == 5);
        b = 1;
    }
}

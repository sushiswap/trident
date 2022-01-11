// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

error Locked();

abstract contract Lock {
    uint256 internal unlocked;
    modifier lock() {
        if (unlocked == 2) revert Locked();
        unlocked = 2;
        _;
        unlocked = 1;
    }
}
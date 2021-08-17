// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.5.0;

/// @notice Wrapped ETH (v9) interface.
interface IWETH {
    function withdraw(uint256) external;
}

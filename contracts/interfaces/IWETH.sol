// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Minimal wrapped ether (v9) interface.
interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

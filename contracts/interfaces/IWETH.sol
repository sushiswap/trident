// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.5.0;

/// @notice Interface for wrapped ether (v9) interactions
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

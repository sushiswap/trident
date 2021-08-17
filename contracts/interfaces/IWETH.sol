// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.5.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Wrapped ETH (v9) interface.
interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;
}

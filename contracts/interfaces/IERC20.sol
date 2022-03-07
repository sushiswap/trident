// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @dev Use a library or custom safeTransfer{From} functions when dealing with unknown tokens!
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

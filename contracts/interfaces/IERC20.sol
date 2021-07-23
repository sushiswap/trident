// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

/// @notice Interface for ERC-20 token with EIP-2612 {permit} extension
interface IERC20 { 
    /// @dev ERC-20:
    function allowance(address owner, address spender) external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function totalSupply() external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
    event Approval(address indexed owner, address indexed spender, uint amount);
    event Transfer(address indexed from, address indexed to, uint amount);
    /// @dev EIP-2612:
    function permit(address owner, address spender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

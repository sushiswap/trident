// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

/// @notice Interface for ERC-20 token interactions with {permit} extensions
interface IERC20 { 
    /// @dev ERC-20:
    function allowance(address owner, address spender) external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function totalSupply() external view returns (uint);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @dev EIP-2612:
    function permit(
        address owner, 
        address spender, 
        uint256 amount, 
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external;
    /// @dev DAI-like {permit}:
    function permitAllowed(
        address owner,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Generic contract exposing the permit functionality.
abstract contract TridentPermit {
    error PermitFailed();

    /// @notice Provides EIP-2612 signed approval for this contract to spend user tokens.
    /// @param token Address of ERC-20 token.
    /// @param amount Token amount to grant spending right over.
    /// @param deadline Termination for signed approval (UTC timestamp in seconds).
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    function permitThis(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        (bool success, ) = token.call(abi.encodeWithSelector(0xd505accf, msg.sender, address(this), amount, deadline, v, r, s)); // permit(address,address,uint256,uint256,uint8,bytes32,bytes32).
        if (!success) revert PermitFailed();
    }

    /// @notice Provides DAI-derived signed approval for this contract to spend user tokens.
    /// @param token Address of ERC-20 token.
    /// @param nonce Token owner's nonce - increases at each call to {permit}.
    /// @param expiry Termination for signed approval - UTC timestamp in seconds.
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    function permitThisAllowed(
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        (bool success, ) = token.call(abi.encodeWithSelector(0x8fcbaf0c, msg.sender, address(this), nonce, expiry, true, v, r, s)); // permit(address,address,uint256,uint256,bool,uint8,bytes32,bytes32).
        if (!success) revert PermitFailed();
    }
}

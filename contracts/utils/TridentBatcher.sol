// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Contract for batching Trident exchange interactions and signed approvals.
contract TridentBatcher {
    /// @notice Provides batch function calls for this contract and returns the data from all of them if they all succeed.
    /// @dev Adapted from Uniswap Labs - Uniswap/uniswap-v3-periphery/blob/main/contracts/base/Multicall.sol, License-Identifier: GPL-2.0-or-later.
    /// @dev The `msg.value` should not be trusted for any method callable from this function.
    /// @param data Encoded function data for each of the calls to make to this contract.
    /// @return results The results from each of the calls passed in via data.
    function batch(bytes[] calldata data) 
        external 
        payable 
        returns (bytes[] memory results) 
    {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                // @dev Next 5 lines from https://ethereum.stackexchange.com/a/83577.
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }
            results[i] = result;
        }
    }
    
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
        (bool success, ) = token.call(abi.encodeWithSelector(
            0xd505accf, msg.sender, address(this), amount, deadline, v, r, s)); // @dev permit(address,address,uint256,uint256,uint8,bytes32,bytes32).
        require(success, "ChefHelper: PERMIT_FAILED");
    }
    
    /// @notice Provides DAI-derived signed approval for this contract to spend user tokens.
    /// @param token Address of ERC-20 token.
    /// @param nonce Token owner's nonce  - increases at each call to {permit}.
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
        (bool success, ) = token.call(abi.encodeWithSelector(
            0x8fcbaf0c, msg.sender, address(this), nonce, expiry, true, v, r, s)); // @dev permit(address,address,uint256,uint256,bool,uint8,bytes32,bytes32).
        require(success, "ChefHelper: PERMIT_FAILED");
    }
}

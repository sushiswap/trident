// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./interfaces/IBentoBoxMinimal.sol";
import "./interfaces/IMasterDeployer.sol";
import "./interfaces/IWETH.sol";
import "./TridentBatchable.sol";
import "./TridentPermit.sol";

/// @notice Trident router helper contract.
abstract contract RouterHelper is TridentPermit, TridentBatchable {
    error ETHtransferFailed();
    error TransferFailed();
    error TransferFromFailed();

    /// @notice BentoBox token vault.
    IBentoBoxMinimal public immutable bento;
    /// @notice Trident AMM master deployer contract.
    IMasterDeployer public immutable masterDeployer;
    /// @notice ERC-20 token for wrapped ETH (v9).
    IWETH internal immutable wETH;
    /// @notice The user should use 0x0 if they want to deposit ETH
    address constant USE_ETHEREUM = address(0);

    constructor(
        IBentoBoxMinimal _bento,
        IMasterDeployer _masterDeployer,
        IWETH _wETH
    ) {
        bento = _bento;
        masterDeployer = _masterDeployer;
        wETH = _wETH;
        _bento.registerProtocol();
    }

    function deployPool(address factory, bytes calldata deployData) external payable returns (address) {
        return masterDeployer.deployPool(factory, deployData);
    }

    /// @notice Helper function to allow batching of BentoBox master contract approvals so the first trade can happen in one transaction.
    function approveMasterContract(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        bento.setMasterContractApproval(msg.sender, address(this), true, v, r, s);
    }

    /// @notice Provides balance check on this contract.
    /// @param token Address of ERC-20 token.
    /// @return balance Token amount held by this contract.
    function balanceOfThis(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Provides 'safe' ERC-20 {transfer} for tokens that don't consistently return true/false.
    /// @param token Address of ERC-20 token.
    /// @param recipient Account to send tokens to.
    /// @param amount Token amount to send.
    /// @dev Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SafeTransferLib.sol).
    function safeTransfer(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        bool callStatus;

        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata to memory piece by piece:
            mstore(freeMemoryPointer, 0xa9059cbb00000000000000000000000000000000000000000000000000000000) // Begin with the function selector.
            mstore(add(freeMemoryPointer, 4), and(recipient, 0xffffffffffffffffffffffffffffffffffffffff)) // Mask and append the "to" argument.
            mstore(add(freeMemoryPointer, 36), amount) // Finally append the "amount" argument. No mask as it's a full 32 byte value.

            // Call the token and store if it succeeded or not.
            // We use 68 because the calldata length is 4 + 32 * 2.
            callStatus := call(gas(), token, 0, freeMemoryPointer, 68, 0, 0)
        }

        if (!didLastOptionalReturnCallSucceed(callStatus)) revert TransferFailed();
    }

    /// @notice Provides 'safe' ERC-20 {transferFrom} for tokens that don't consistently return true/false.
    /// @param token Address of ERC-20 token.
    /// @param sender Account to send tokens from.
    /// @param recipient Account to send tokens to.
    /// @param amount Token amount to send.
    /// @dev Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SafeTransferLib.sol).
    function safeTransferFrom(
        address token,
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        bool callStatus;

        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata to memory piece by piece:
            mstore(freeMemoryPointer, 0x23b872dd00000000000000000000000000000000000000000000000000000000) // Begin with the function selector.
            mstore(add(freeMemoryPointer, 4), and(sender, 0xffffffffffffffffffffffffffffffffffffffff)) // Mask and append the "from" argument.
            mstore(add(freeMemoryPointer, 36), and(recipient, 0xffffffffffffffffffffffffffffffffffffffff)) // Mask and append the "to" argument.
            mstore(add(freeMemoryPointer, 68), amount) // Finally append the "amount" argument. No mask as it's a full 32 byte value.

            // Call the token and store if it succeeded or not.
            // We use 100 because the calldata length is 4 + 32 * 3.
            callStatus := call(gas(), token, 0, freeMemoryPointer, 100, 0, 0)
        }

        if (!didLastOptionalReturnCallSucceed(callStatus)) revert TransferFromFailed();
    }

    /// @notice Provides `wETH` {withdraw}.
    /// @param amount Token amount to unwrap into ETH.
    function withdrawFromWETH(uint256 amount) internal {
        wETH.withdraw(amount);
    }

    /// @notice Provides 'safe' ETH transfer.
    /// @param recipient Account to send ETH to.
    /// @param amount ETH amount to send.
    /// @dev Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SafeTransferLib.sol).
    function safeTransferETH(address recipient, uint256 amount) internal {
        bool callStatus;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            callStatus := call(gas(), recipient, amount, 0, 0, 0, 0)
        }

        if (!callStatus) revert ETHtransferFailed();
    }

    /// @notice Provides feedback on assembly calls.
    /// @param callStatus Input of call.
    function didLastOptionalReturnCallSucceed(bool callStatus) private pure returns (bool success) {
        assembly {
            // Get how many bytes the call returned.
            let returnDataSize := returndatasize()

            // If the call reverted:
            if iszero(callStatus) {
                // Copy the revert message into memory.
                returndatacopy(0, 0, returnDataSize)

                // Revert with the same message.
                revert(0, returnDataSize)
            }

            switch returnDataSize
            case 32 {
                // Copy the return data into memory.
                returndatacopy(0, 0, returnDataSize)

                // Set success to whether it returned true.
                success := iszero(iszero(mload(0)))
            }
            case 0 {
                // There was no return data.
                success := 1
            }
            default {
                // It returned some malformed input.
                success := 0
            }
        }
    }
}

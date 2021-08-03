// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Library for optimized Trident exchange interactions - adapted from boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol, License-Identifier: MIT.
library TridentHelper {
    /// @notice Provides gas-optimized balance check on this contract to avoid redundant extcodesize check in addition to returndatasize check.
    /// @dev Reverts on failed {balanceOf}.
    /// @param token Address of ERC-20 token.
    /// @return amount Token amount.
    function balanceOfThis(address token) internal view returns (uint256 amount) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(0x70a08231, address(this))); // @dev balanceOf(address).
        require(success && data.length >= 32, "BALANCE_OF_FAILED");
        amount = abi.decode(data, (uint256));
    }

    /// @notice Provides safe ERC20.transfer for tokens that do not consistently return true/false.
    /// @dev Reverts on failed {transfer}.
    /// @param token Address of ERC-20 token.
    /// @param recipient Account to send tokens to.
    /// @param amount The token amount to send.
    function safeTransfer(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, recipient, amount)); // @dev transfer(address,uint256).
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    /// @notice Provides safe ERC20.transferFrom for tokens that do not consistently return true/false.
    /// @dev Reverts on failed {transferFrom}.
    /// @param token Address of ERC-20 token.
    /// @param from Account to send tokens from.
    /// @param recipient Account to send tokens to.
    /// @param amount Token amount to send.
    function safeTransferFrom(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, recipient, amount)); // @dev transferFrom(address,address,uint256).
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    /// @notice Provides gas-optimized {balanceOfThis} check on `wETH` and matching {withdraw}.
    /// @dev Reverts on failed {withdraw}.
    /// @param wETH Address of ERC-20 token for wrapped ETH.
    function withdrawFromWETH(address wETH, uint256 balanceWETH) internal {
        (bool success, ) = wETH.call(abi.encodeWithSelector(0x2e1a7d4d, balanceWETH)); // @dev withdraw(uint256).
        require(success, "WITHDRAW_FROM_WETH_FAILED");
    }

    /// @notice Provides safe ETH transfer.
    /// @dev Reverts on failed {call}.
    /// @param recipient Account to send ETH.
    /// @param amount ETH amount to send.
    function safeTransferETH(address recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH_TRANSFER_FAILED");
    }
}

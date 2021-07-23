// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

/// @notice Interface for Trident pool calls with data context.
interface ITridentCallee {
    function tridentCallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata data
    ) external;
}

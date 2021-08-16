// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Interface for Trident pool interactions with data context.
interface ITridentCallee {
    function tridentSwapCallback(bytes calldata data) external;

    function tridentMintCallback(bytes calldata data) external;
}

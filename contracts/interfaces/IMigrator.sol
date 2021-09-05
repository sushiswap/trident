// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident pool migrator interface for legacy SushiSwap.
interface IMigrator {
    /// @notice Returns desired amount of liquidity tokens for migration.
    function desiredLiquidity() external view returns (uint256);
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident pool migrator interface for legacy SushiSwap.
interface IMigrator {
    /// @notice Returns liquidity token balance per ERC-20.
    function balanceOf(address account) external view returns (uint256);
    /// @notice Returns Trident pool from configuration data.
    function configAddress(bytes memory deployData) external view returns (address);
    /// @notice Returns desired amount of liquidity tokens for migration.
    function desiredLiquidity() external view returns (uint256);
    /// @notice Returns the first token in the pair pool.
    function token0() external view returns (address);
    /// @notice Returns the second token in the pair pool.
    function token1() external view returns (address);
    /// @notice Returns the token supply in the pair pool per ERC-20.
    function totalSupply() external view returns (uint256);
    /// @notice Deposits a token into BentoBox.
    function deposit(address token, address from, address to, uint256 amount, uint256 share) external payable returns (uint256 amountOut, uint256 shareOut);
    /// @notice Deploys a new Trident pool.
    function deployPool(bytes calldata deployData) external returns (address);
    /// @notice Burns liquidity tokens from a legacy SushiSwap pair pool.
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    /// @notice Mints Trident pool liquidity tokens.
    function mint(bytes calldata data) external returns (uint256 liquidity);
    /// @notice Pulls tokens per ERC-20.
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

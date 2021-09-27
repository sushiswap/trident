// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident pool deployment interface.
interface IPoolDeployer {
    function deployPool(bytes calldata _deployData) external returns (address pool, address[] memory tokens);
}

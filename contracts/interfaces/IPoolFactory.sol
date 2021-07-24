// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Interface for Trident pool deployment
interface IPoolFactory {
    function deployPool(bytes calldata _deployData) external returns (address);
}

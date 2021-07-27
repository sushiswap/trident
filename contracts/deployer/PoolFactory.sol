// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../interfaces/IPoolFactory.sol";

import "./PoolTemplate.sol";

/**
 * @author Mudit Gupta
 */
contract PoolFactory is IPoolFactory {
    // Consider deploying via an upgradable proxy to allow upgrading pools in the future

    function deployPool(bytes memory _deployData) external override returns (address) {
        return address(new PoolTemplate(_deployData));
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "../pool/PoolDeployer.sol";

import "./PoolTemplate.sol";

/**
 * @author Mudit Gupta
 */
contract PoolFactory is PoolDeployer {
    // Consider deploying via an upgradable proxy to allow upgrading pools in the future
    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external override returns (address pool, address[] memory tokens) {
        (address tokenA, address tokenB, uint256 configValue) = abi.decode(_deployData, (address, address, uint256));
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
            _deployData = abi.encode(tokenA, tokenB, configValue);
        }
        tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        pool = address(new PoolTemplate(_deployData));
        _registerPool(pool, tokens, keccak256(_deployData));
    }
}

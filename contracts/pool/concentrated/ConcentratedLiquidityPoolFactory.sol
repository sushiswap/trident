// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./ConcentratedLiquidityPool.sol";
import "../PoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Concentrated Liquidity Pool with configurations.
/// @author Mudit Gupta.
contract ConcentratedLiquidityPoolFactory is PoolDeployer {
    address immutable positionManager;

    constructor(address _masterDeployer, address _positionManager) PoolDeployer(_masterDeployer) {
        positionManager = _positionManager;
    }

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, uint24 swapFee, uint160 price) = abi.decode(_deployData, (address, address, uint24, uint160));
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
            _deployData = abi.encode(tokenA, tokenB, swapFee, price);
        }
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        // @dev Salt is not actually needed since `_deployData` is part of creationCode and already contains the salt.
        bytes32 salt = keccak256(_deployData);
        pool = address(new ConcentratedLiquidityPool{salt: salt}(_deployData, masterDeployer, positionManager));
        _registerPool(pool, tokens, salt);
    }
}

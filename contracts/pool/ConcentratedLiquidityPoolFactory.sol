// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./ConcentratedLiquidityPool.sol";

/**
 * @author Mudit Gupta
 */
contract ConcentratedLiquidityPoolFactory {
    // Consider deploying via an upgradable proxy to allow upgrading pools in the future
    
    function deployPool(bytes memory _deployData) external returns (address) {
        // return address(new ConcentratedLiquidityPool(_deployData, msg.sender));
    }
}

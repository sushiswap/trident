// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./BasicMirinPool.sol";

/**
 * @author Mudit Gupta
 */
contract BasicMirinPoolFactory {
    // Consider deploying via an upgradable proxy to allow upgrading pools in the future

    function deployPoolLogic(bytes memory _deployData) external returns (address) {
        return address(new BasicMirinPool(_deployData));
    }
}

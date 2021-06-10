// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./ConstantProductPool.sol";

/**
 * @author Mudit Gupta
 */
contract ConstantProductPoolFactory {
    // Consider deploying via an upgradable proxy to allow upgrading pools in the future

    function deployPoolLogic(bytes memory _deployData) external returns (address) {
        return address(new ConstantProductPool(_deployData, msg.sender));
    }
}

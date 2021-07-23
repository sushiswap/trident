// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "./ConstantProductPoolWithTWAP.sol";

/**
 * @author Mudit Gupta
 */
contract ConstantProductPoolWithTWAPFactory {
    // Consider deploying via an upgradable proxy to allow upgrading pools in the future

    function deployPool(bytes memory _deployData) external returns (address) {
        return address(new ConstantProductPoolWithTWAP(_deployData, msg.sender));
    }
}

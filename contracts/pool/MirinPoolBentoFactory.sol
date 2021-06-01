// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./MirinPoolBento.sol";

/**
 * @author Mudit Gupta
 */
contract MirinPoolFactory {
    // Consider deploying via an upgradable proxy to allow upgrading pools in the future

    function deployPoolLogic(bytes memory _deployData) external returns (address) {
        return address(new MirinPoolBento(_deployData));
    }
}

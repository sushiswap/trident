// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./ConstantProductPool.sol";

/// @notice Contract for deploying Trident exchange Constant Product Pool with configurations.
/// @author Mudit Gupta.
contract ConstantProductPoolFactory {
    function deployPool(bytes memory _deployData) external returns (address pool) {
        pool = address(new ConstantProductPool(_deployData, msg.sender));
    }
}

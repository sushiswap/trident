// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./HybridPool.sol";

/// @notice Contract for deploying Trident exchange Hybrid Pool with configurations.
/// @author Mudit Gupta.
contract HybridPoolFactory {
    function deployPool(bytes memory _deployData) external returns (address pool) {
        pool = address(new HybridPool(_deployData, msg.sender));
    }
}

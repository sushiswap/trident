// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./ConstantProductPoolWithTWAP.sol";

/// @notice Contract for deploying Trident exchange Constant Product Pool with configurations and TWAP.
/// @author Mudit Gupta.
contract ConstantProductPoolWithTWAPFactory {
    function deployPool(bytes memory _deployData) external returns (address pool) {
        pool = address(new ConstantProductPoolWithTWAP(_deployData, msg.sender));
    }
}

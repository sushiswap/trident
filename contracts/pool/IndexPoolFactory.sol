// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IndexPool.sol";
import "./PoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Index Pool with configurations.
/// @author Mudit Gupta
contract IndexPoolFactory is PoolDeployer {
    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address[] memory tokens, , ) = abi.decode(_deployData, (address[], uint256[], uint256));

        pool = _deployPool(tokens, type(IndexPool).creationCode, _deployData);
    }
}

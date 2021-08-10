// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IndexPool.sol";
import "./ArrayPoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Index Pool with configurations.
/// @author Mudit Gupta
contract IndexPoolFactory is ArrayPoolDeployer {
    constructor(address _masterDeployer) ArrayPoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address[] memory _tokens, ,) = abi.decode(
            _deployData,
            (address[], uint256[], uint256)
        );

        pool = _deployPool(_tokens, type(IndexPool).creationCode, _deployData);
    }
}

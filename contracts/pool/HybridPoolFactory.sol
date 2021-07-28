// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./HybridPool.sol";
import "./PairPoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Hybrid Pool with configurations.
/// @author Mudit Gupta.
contract HybridPoolFactory is PairPoolDeployer {
    constructor(address _masterDeployer) PairPoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, , ) = abi.decode(_deployData, (address, address, uint256, uint256));
        pool = _deployPool(tokenA, tokenB, type(HybridPool).creationCode, _deployData);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./HybridPool.sol";
import "./PairPoolDeployer.sol";

/**
 * @author Mudit Gupta
 */
contract HybridPoolFactory is PairPoolDeployer {
    constructor(address _masterDeployer) PairPoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address) {
        (address tokenA, address tokenB, , ) = abi.decode(_deployData, (address, address, uint256, uint256));
        return _deployPool(address(tokenA), address(tokenB), type(HybridPool).creationCode, _deployData);
    }
}

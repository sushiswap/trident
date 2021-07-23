// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "./ConstantProductPool.sol";
import "./PairPoolDeployer.sol";

/**
 * @author Mudit Gupta
 */
contract ConstantProductPoolFactory is PairPoolDeployer {
    constructor(address _masterDeployer) PairPoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address) {
        (IERC20 tokenA, IERC20 tokenB, ) = abi.decode(_deployData, (IERC20, IERC20, uint256));
        return _deployPool(address(tokenA), address(tokenB), type(ConstantProductPool).creationCode, _deployData);
    }
}

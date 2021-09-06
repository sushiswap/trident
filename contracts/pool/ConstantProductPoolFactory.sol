// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./ConstantProductPool.sol";
import "./PoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Constant Product Pool with configurations.
/// @author Mudit Gupta.
contract ConstantProductPoolFactory is PoolDeployer {
    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, uint256 swapFee, bool twapSupport) = abi.decode(_deployData, (address, address, uint256, bool));
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
            _deployData = abi.encode(tokenA, tokenB, swapFee, twapSupport);
        }
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        pool = _deployPool(tokens, type(ConstantProductPool).creationCode, _deployData);
    }
}

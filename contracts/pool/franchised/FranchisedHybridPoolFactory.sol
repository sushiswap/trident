// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0;

import "./FranchisedHybridPool.sol";
import "../../abstract/PoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Franchised Hybrid Product Pool with configurations.
/// @author Mudit Gupta.
contract FranchisedHybridPoolFactory is PoolDeployer {
    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, uint256 swapFee, uint256 a, address whiteListManager, address operator, bool level2) = abi.decode(
            _deployData,
            (address, address, uint256, uint256, address, address, bool)
        );
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        // @dev Strips any extra data.
        _deployData = abi.encode(tokenA, tokenB, swapFee, a, whiteListManager, operator, level2);
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        // @dev Salt is not actually needed since `_deployData` is part of creationCode and already contains the salt.
        bytes32 salt = keccak256(_deployData);
        pool = address(new FranchisedHybridPool{salt: salt}(_deployData, masterDeployer));
        _registerPool(pool, tokens, salt);
    }
}

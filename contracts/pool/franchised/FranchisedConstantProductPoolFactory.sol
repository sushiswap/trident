// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./FranchisedConstantProductPool.sol";
import "../../abstract/PoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Franchised Constant Product Pool with configurations.
/// @author Mudit Gupta.
contract FranchisedConstantProductPoolFactory is PoolDeployer {
    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, uint256 swapFee, bool twapSupport, address whiteListManager, address operator, bool level2) = abi
            .decode(_deployData, (address, address, uint256, bool, address, address, bool));
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        // @dev Strips any extra data.
        _deployData = abi.encode(tokenA, tokenB, swapFee, twapSupport, whiteListManager, operator, level2);

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        // @dev Salt is not actually needed since `_deployData` is part of creationCode and already contains the salt.
        bytes32 salt = keccak256(_deployData);
        pool = address(new FranchisedConstantProductPool{salt: salt}(_deployData, masterDeployer));
        _registerPool(pool, tokens, salt);
    }
}

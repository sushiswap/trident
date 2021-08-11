// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IndexPool.sol";

/// @notice Trident exchange pool deployer for whitelisted token array template factories.
/// @author Mudit Gupta
contract ArrayPoolDeployer {
    mapping(bytes => address) public configAddress;
    address public immutable masterDeployer;

    constructor(address _masterDeployer) {
        require(_masterDeployer != address(0), "ZERO_ADDRESS");
        masterDeployer = _masterDeployer;
    }

    function _deployPool(
        address[] memory tokens,
        bytes memory creationCode,
        bytes memory deployData
    ) internal returns (address pool) {
        for (uint8 i = 0; i < tokens.length; i++) {
            require(tokens[i] < tokens[i++], "INVALID_TOKEN_ORDER");
        }
        
        require(configAddress[deployData] == address(0), "POOL_ALREADY_DEPLOYED");

        // NB Salt is not actually needed since creationCodeWithConfig already contains the salt.
        bytes32 salt = keccak256(deployData);

        bytes memory creationCodeWithConfig = abi.encodePacked(creationCode, abi.encode(deployData, masterDeployer));

        assembly {
            pool := create2(0, add(creationCodeWithConfig, 32), mload(creationCodeWithConfig), salt)
            if iszero(extcodesize(pool)) {
                revert(0, 0)
            }
        }
        configAddress[deployData] = pool;
    }
}

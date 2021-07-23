// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "./ConstantProductPool.sol";

/**
 * @author Mudit Gupta
 */
contract PairPoolDeployer {
    mapping(address => mapping(address => address[])) public pools;
    mapping(bytes => address) public configAddress;
    address public immutable masterDeployer;

    constructor(address _masterDeployer) {
        require(_masterDeployer != address(0), "ZERO_ADDRESS");
        masterDeployer = _masterDeployer;
    }

    function _deployPool(
        address token0,
        address token1,
        bytes memory creationCode,
        bytes memory deployData
    ) internal returns (address pair) {
        require(token0 < token1, "INVALID_TOKEN_ORDER");
        require(configAddress[deployData] == address(0), "POOL_ALREADY_DEPLOYED");

        uint256 pairNonce = pools[token0][token1].length;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, pairNonce));

        bytes memory creationCodeWithConfig = abi.encodePacked(creationCode, abi.encode(deployData, masterDeployer));

        assembly {
            pair := create2(0, add(creationCodeWithConfig, 32), mload(creationCodeWithConfig), salt)
            if iszero(extcodesize(pair)) {
                revert(0, 0)
            }
        }
        pools[token0][token1].push(pair);
        configAddress[deployData] = pair;
    }

    function poolsCount(address token0, address token1) external view returns (uint256) {
        return pools[token0][token1].length;
    }
}

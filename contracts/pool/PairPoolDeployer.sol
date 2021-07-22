// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "./ConstantProductPool.sol";

/**
 * @author Mudit Gupta
 */
contract PairPoolDeployer {
    mapping(address => mapping(address => address[])) public pools;
    address public immutable masterDeployer;

    constructor(address _masterDeployer) {
        require(_masterDeployer != address(0), "ZERO_ADDRESS");
        masterDeployer = _masterDeployer;
    }

    function _deployPool(
        address token0,
        address token1,
        bytes memory creationCode
    ) internal returns (address pair) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        uint256 pairNonce = pools[token0][token1].length;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, pairNonce));
        assembly {
            pair := create2(0, add(creationCode, 32), mload(creationCode), salt)
            if iszero(extcodesize(pair)) {
                revert(0, 0)
            }
        }
        pools[token0][token1].push(pair);
    }

    function poolsCount(address token0, address token1) external view returns (uint256) {
        return pools[token0][token1].length;
    }
}

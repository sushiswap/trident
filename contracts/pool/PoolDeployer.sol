// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident pool deployer for whitelisted template factories.
/// @author Mudit Gupta.
contract PoolDeployer {
    address public immutable masterDeployer;

    mapping(address => mapping(address => address[])) public pools;
    mapping(bytes => address) public configAddress;

    constructor(address _masterDeployer) {
        require(_masterDeployer != address(0), "ZERO_ADDRESS");
        masterDeployer = _masterDeployer;
    }

    function _deployPool(
        address[] memory tokens,
        bytes memory creationCode,
        bytes memory deployData
    ) internal returns (address pool) {
        require(configAddress[deployData] == address(0), "POOL_ALREADY_DEPLOYED");
        // @dev Salt is not actually needed since `creationCodeWithConfig` already contains the salt.
        bytes32 salt = keccak256(deployData);
        // @dev Data padded after the creation code becomes input to the contructor of the deployed contract.
        bytes memory creationCodeWithConfig = abi.encodePacked(creationCode, abi.encode(deployData, masterDeployer));
        // @dev Deploy the contract - revert if deployment fails.
        assembly {
            pool := create2(0, add(creationCodeWithConfig, 32), mload(creationCodeWithConfig), salt)
            if iszero(extcodesize(pool)) {
                revert(0, 0)
            }
        }
        // @dev Store the address of the deployed contract.
        configAddress[deployData] = pool;
        // @dev This is safe from underflow - null token array would cause deployment to fail via gas limit.
        unchecked {
            for (uint256 i = 0; i < tokens.length - 1; i++) {
                require(tokens[i] < tokens[i + 1], "INVALID_TOKEN_ORDER");
                for (uint256 j = i + 1; j < tokens.length; j++) {
                    pools[tokens[i]][tokens[j]].push(pool);
                }
            }
        }
    }

    function poolsCount(address token0, address token1) external view returns (uint256 count) {
        count = pools[token0][token1].length;
    }

    function getPools(
        address token0,
        address token1,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (address[] memory pairPools) {
        pairPools = new address[](endIndex - startIndex);
        for (uint256 i = 0; startIndex < endIndex; i++) {
            pairPools[i] = pools[token0][token1][startIndex];
            startIndex++;
        }
    }
}

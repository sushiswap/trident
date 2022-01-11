// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >= 0.8.0;

import "../interfaces/IPoolFactory.sol";
import "./PoolTemplateMock.sol";
import "../abstract/MasterDeployerGuard.sol";

error InvalidTokenOrder();
error ZeroAddress();

contract PoolFactoryMock is MasterDeployerGuard {

    mapping(address => mapping(address => address[])) public pools;
    
    mapping(bytes32 => address) public configAddress;
    constructor(address _masterDeployer) MasterDeployerGuard(_masterDeployer) {
         if (_masterDeployer == address(0)) revert ZeroAddress();
    }

    function deployPool(bytes memory _deployData) external onlyMaster returns (address pool) {
        (address tokenA, address tokenB) = abi.decode(_deployData, (address, address));

        address[] memory tokens = new address[](2);
        
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        bytes32 salt = keccak256(_deployData);

        pool = address(new PoolTemplateMock{salt: salt}(_deployData));

        // @dev Store the address of the deployed contract.
        configAddress[salt] = pool;
        
        // @dev Attacker used underflow, it was not very effective. poolimon!
        // null token array would cause deployment to fail via out of bounds memory axis/gas limit.
        unchecked {
            for (uint256 i; i < tokens.length - 1; i++) {
                if (tokens[i] >= tokens[i + 1]) revert InvalidTokenOrder();
                for (uint256 j = i + 1; j < tokens.length; j++) {
                    pools[tokens[i]][tokens[j]].push(pool);
                    pools[tokens[j]][tokens[i]].push(pool);
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
        uint256 count
    ) external view returns (address[] memory pairPools) {
        pairPools = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            pairPools[i] = pools[token0][token1][startIndex + i];
        }
    }
}

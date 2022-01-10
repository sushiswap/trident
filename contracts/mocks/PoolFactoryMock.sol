// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >= 0.8.0;

import "../interfaces/IPoolFactory.sol";
import "../deployer/PoolDeployer.sol";
import "./PoolTemplateMock.sol";

contract PoolFactoryMock is PoolDeployer {
    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}
    
    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB) = abi.decode(_deployData, (address, address));

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        bytes32 salt = keccak256(_deployData);
        pool = address(new PoolTemplateMock{salt: salt}(_deployData));

        _registerPool(pool, tokens, salt);
    }
}

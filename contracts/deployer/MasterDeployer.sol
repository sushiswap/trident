// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./PoolProxy.sol";
import "./PoolFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @author Mudit Gupta
 */
contract MasterDeployer is Ownable {
    mapping (address => bool) public whitelistedFactories;

    constructor() Ownable() {}

    function deployPool(address _factory, bytes memory _deployData, bytes memory _initData) external returns (address) {
        require(whitelistedFactories[_factory], "Factory not whitelisted");
        address logic = PoolFactory(_factory).deployPoolLogic(_deployData);
        return address(new PoolProxy(logic, _initData));
    }

    function addToWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = true;
    }

    function removeFromWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = false;
    }
}

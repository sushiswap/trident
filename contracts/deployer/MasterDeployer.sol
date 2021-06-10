// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./PoolProxy.sol";
import "./PoolFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @author Mudit Gupta
 */
contract MasterDeployer is Ownable {
    event NewPoolCreated(address indexed poolAddress);

    mapping (address => bool) public whitelistedFactories;

    mapping (address => bool) public pool;

    uint256 public barFee;

    address public immutable barFeeTo;
    address public immutable bento;

    uint256 internal constant MAX_FEE = 10000; // 100%

    constructor(uint256 _barFee, address _barFeeTo, address _bento) Ownable() {
        require(_barFee <= MAX_FEE, "INVALID_BAR_FEE");
        require(address(_barFeeTo) != address(0), "ZERO_ADDRESS");
        require(address(_bento) != address(0), "ZERO_ADDRESS");

        barFee = _barFee;
        barFeeTo = _barFeeTo;
        bento = _bento;
    }

    function deployPool(address _factory, bytes memory _deployData, bytes memory _initData) external returns (address poolAddress) {
        require(whitelistedFactories[_factory], "Factory not whitelisted");
        address logic = PoolFactory(_factory).deployPoolLogic(_deployData);
        poolAddress = address(new PoolProxy(logic, _initData));
        pool[poolAddress] = true;
        emit NewPoolCreated(poolAddress);
    }

    function addToWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = true;
    }

    function removeFromWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = false;
    }

    function setBarFee(uint256 _barFee) external onlyOwner {
        require(_barFee <= MAX_FEE, "INVALID_BAR_FEE");
        barFee = _barFee;
    }
}

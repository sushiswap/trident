// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "../interfaces/IPoolFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @author Mudit Gupta
 */
contract MasterDeployer is Ownable {
    event NewPoolCreated(address indexed poolAddress);

    mapping(address => bool) public whitelistedFactories;

    uint256 public barFee;

    address public immutable barFeeTo;
    address public immutable bento;

    uint256 internal constant MAX_FEE = 10000; // 100%

    address[] public pools;

    constructor(
        uint256 _barFee,
        address _barFeeTo,
        address _bento
    ) Ownable() {
        require(_barFee <= MAX_FEE, "INVALID_BAR_FEE");
        require(address(_barFeeTo) != address(0), "ZERO_ADDRESS");
        require(address(_bento) != address(0), "ZERO_ADDRESS");

        barFee = _barFee;
        barFeeTo = _barFeeTo;
        bento = _bento;
    }

    function deployPool(address _factory, bytes calldata _deployData) external returns (address poolAddress) {
        require(whitelistedFactories[_factory], "Factory not whitelisted");
        poolAddress = IPoolFactory(_factory).deployPool(_deployData);
        pools.push(poolAddress);
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

    function poolsCount() external view returns (uint256) {
        return pools.length;
    }
}

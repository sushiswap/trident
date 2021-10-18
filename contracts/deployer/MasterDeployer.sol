// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../utils/TridentOwnable.sol";

/// @notice Trident pool deployer contract with template factory whitelist.
/// @author Mudit Gupta.
contract MasterDeployer is TridentOwnable {
    event DeployPool(address indexed factory, address indexed pool, bytes deployData);
    event AddToWhitelist(address indexed factory);
    event RemoveFromWhitelist(address indexed factory);
    event BarFeeUpdated(uint256 indexed barFee);

    uint256 public barFee;
    address public immutable barFeeTo;
    address public immutable bento;
    address[] public factoryList;

    uint256 internal constant MAX_FEE = 10000; // @dev 100%.

    mapping(address => bool) public pools;
    mapping(address => Type) public factories;
    
    struct Type {
        bool whitelisted;
        bytes32 identifier;
    }

    constructor(
        uint256 _barFee,
        address _barFeeTo,
        address _bento
    ) {
        require(_barFee <= MAX_FEE, "INVALID_BAR_FEE");
        require(_barFeeTo != address(0), "ZERO_ADDRESS");
        require(_bento != address(0), "ZERO_ADDRESS");

        barFee = _barFee;
        barFeeTo = _barFeeTo;
        bento = _bento;
    }

    function deployPool(address _factory, bytes calldata _deployData) external returns (address pool) {
        require(factories[_factory].whitelisted, "FACTORY_NOT_WHITELISTED");
        pool = IPoolFactory(_factory).deployPool(_deployData);
        pools[pool] = true;
        emit DeployPool(_factory, pool, _deployData);
    }

    function addToWhitelist(address _factory) external onlyOwner {
        bytes32 identifier = IPool(_factory).poolIdentifier();
        for (uint256 i = 0; i < factoryList.length; i++) {
            require(identifier != factories[factoryList[i]].identifier, "FACTORY_NOT_UNIQUE");
        }
        factories[_factory] = Type(true, identifier);
        factoryList.push(_factory);
        emit AddToWhitelist(_factory);
    }

    function removeFromWhitelist(address _factory) external onlyOwner {
        factories[_factory].whitelisted = false;
        emit RemoveFromWhitelist(_factory);
    }

    function setBarFee(uint256 _barFee) external onlyOwner {
        require(_barFee <= MAX_FEE, "INVALID_BAR_FEE");
        barFee = _barFee;
        emit BarFeeUpdated(_barFee);
    }
}

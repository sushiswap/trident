// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPoolFactory.sol";
import "../utils/TridentOwnable.sol"; 

/// @notice Trident exchange pool deployer for whitelisted template factories.
/// @author Mudit Gupta.
contract MasterDeployer is TridentOwnable {
    event NewPoolCreated(address indexed _factory, address indexed pool);

    mapping(address => bool) public whitelistedFactories;

    uint256 public barFee;

    address public immutable barFeeTo;
    address public immutable bento;

    uint256 internal constant MAX_FEE = 10000; // @dev 100%.

    address[] public pools;

    constructor(
        uint256 _barFee,
        address _barFeeTo,
        address _bento
    ) Ownable() {
        require(_barFee <= MAX_FEE, "MasterDeployer: INVALID_BAR_FEE");
        require(_barFeeTo != address(0), "MasterDeployer: ZERO_ADDRESS");
        require(_bento != address(0), "MasterDeployer: ZERO_ADDRESS");

        barFee = _barFee;
        barFeeTo = _barFeeTo;
        bento = _bento;
    }

    function deployPool(address _factory, bytes calldata _deployData) external returns (address pool) {
        require(whitelistedFactories[_factory], "MasterDeployer: FACTORY_NOT_WHITELISTED");
        pool = IPoolFactory(_factory).deployPool(_deployData);
        pools.push(pool);
        emit NewPoolCreated(_factory, pool);
    }

    function addToWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = true;
    }

    function removeFromWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = false;
    }

    function setBarFee(uint256 _barFee) external onlyOwner {
        require(_barFee <= MAX_FEE, "MasterDeployer: INVALID_BAR_FEE");
        barFee = _barFee;
    }

    function poolsCount() external view returns (uint256 count) {
        count = pools.length;
    }
}

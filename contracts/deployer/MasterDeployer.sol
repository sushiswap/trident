// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPoolFactory.sol";
import "../interfaces/IMasterDeployer.sol";
import "../utils/TridentOwnable.sol";

/// @notice Trident pool deployer contract with template factory whitelist.
/// @author Mudit Gupta.
contract MasterDeployer is IMasterDeployer, TridentOwnable {
    event DeployPool(address indexed _factory, address indexed pool);

    uint256 public override barFee;
    address public override migrator;

    address public immutable override barFeeTo;
    address public immutable override bento;

    uint256 internal constant MAX_FEE = 10000; /// @dev 100%.

    address[] public pools;

    mapping(address => bool) public override whitelistedFactories;

    /// @notice A mapping of tokens that do not include any pre or post transfer hooks.
    /// @dev Pools consisting only of "clean tokens" can use a less restrictive lock modifier
    mapping(address => bool) public override cleanTokens;

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
        require(whitelistedFactories[_factory], "FACTORY_NOT_WHITELISTED");
        pool = IPoolFactory(_factory).deployPool(_deployData);
        pools.push(pool);
        emit DeployPool(_factory, pool);
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

    function setMigrator(address _migrator) external onlyOwner {
        migrator = _migrator;
    }

    function setCleanTokens(address[] calldata _tokens, bool[] calldata _values) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            cleanTokens[_tokens[i]] = _values[i];
        }
    }

    function poolsCount() external view returns (uint256 count) {
        count = pools.length;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../../interfaces/IWhiteListManager.sol";
import "./FranchisedConcentratedLiquidityPool.sol";
import "../../PoolDeployer.sol";

/// @notice Contract for deploying Trident exchange franchised Concentrated Liquidity Pool with configurations.
/// @author Mudit Gupta.
contract FranchisedConcentratedLiquidityPoolFactory is PoolDeployer {
    IWhiteListManager internal immutable whiteListManager;
    
    constructor(address _masterDeployer, IWhiteListManager _whiteListManager) PoolDeployer(_masterDeployer) {
        whiteListManager = _whiteListManager;
    }

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (
            address tokenA, 
            address tokenB, 
            uint24 swapFee, 
            uint160 price, 
            uint24 tickSpacing,
            address operator,
            bool level2
        ) = abi.decode(
            _deployData,
            (address, address, uint24, uint160, uint24, address, bool)
        );
        
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        // Strips any extra data.
        _deployData = abi.encode(tokenA, tokenB, swapFee, price, tickSpacing, operator, level2);

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        // Salt is not actually needed since `_deployData` is part of creationCode and already contains the salt.
        bytes32 salt = keccak256(_deployData);
        pool = address(new FranchisedConcentratedLiquidityPool{salt: salt}(_deployData, IMasterDeployer(masterDeployer), whiteListManager));
        _registerPool(pool, tokens, salt);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IMigrator.sol";
import "hardhat/console.sol";

/// @notice Trident pool migrator contract for legacy SushiSwap.
contract Migrator {
    IMigrator public immutable bento;
    IMigrator public immutable constantProductPoolFactory;
    address public immutable masterChefV1;
    address public immutable masterChefV2;
    uint256 public desiredLiquidity;

    constructor(
        IMigrator _bento,
        IMigrator _constantProductPoolFactory,
        address _masterChefV1,
        address _masterChefV2
    ) {
        bento = _bento;
        constantProductPoolFactory = _constantProductPoolFactory;
        masterChefV1 = _masterChefV1;
        masterChefV2 = _masterChefV2;
        desiredLiquidity = type(uint256).max;
    }
    
    /// @notice Migration method to replace legacy SushiSwap liquidity tokens with Trident position.
    /// @param oldPool Legacy SushiSwap pair pool.
    /// @return pool Returns confirmed Trident pair pool - this is more useful where migration initializes pair.
    function migrate(IMigrator oldPool) external returns (address pool) {
        require(msg.sender == masterChefV1 || msg.sender == masterChefV2, "NOT_CHEF");
        // @dev Get the `oldPool` pair tokens.
        address token0 = oldPool.token0(); 
        address token1 = oldPool.token1(); 
        
        bytes memory deployData = abi.encode(token0, token1, 10, false);
        
        pool = constantProductPoolFactory.configAddress(deployData);
    
        // @dev If `newPool` is uninitialized, deploy on Trident.
        if (pool == address(0)) pool = constantProductPoolFactory.deployPool(deployData);

        // @dev Check `newPool` LP has not already initialized.
        require(IMigrator(pool).totalSupply() == 0, "PAIR_ALREADY_SUPPLIED");

        // @dev Get `oldPool` LP balance from `MasterChef`.
        uint256 lp = oldPool.balanceOf(msg.sender);
        desiredLiquidity = lp;
        
        if (lp == 0) return pool;
        
        // @dev Pull `oldPool` LP balance from `MasterChef` to `oldPool` for burn.
        oldPool.transferFrom(msg.sender, address(oldPool), lp);

        // @dev Complete LP migration with burn from `oldPool` and mint into `newPool` pair.
        (uint256 amount0, uint256 amount1) = oldPool.burn(address(bento)); 
        
        bento.deposit(token0, address(bento), pool, amount0, 0);
        bento.deposit(token1, address(bento), pool, amount1, 0);
        
        IMigrator(pool).mint(abi.encode(msg.sender));
        
        desiredLiquidity = type(uint256).max;
        return pool;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/TridentBatchable.sol";
import "../utils/TridentPermit.sol";

/// @notice Minimal Trident pool router interface.
interface ITridentRouterMinimal {
    struct TokenInput {
        address token;
        bool native;
        uint256 amount;
    }
    
    /// @notice Add liquidity to a pool.
    /// @param tokenInput Token address and amount to add as liquidity.
    /// @param pool Pool address to add liquidity to.
    /// @param minLiquidity Minimum output liquidity - caps slippage.
    /// @param data Data required by the pool to add liquidity. 
    function addLiquidity(
        TokenInput[] calldata tokenInput,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) external payable returns (uint256 liquidity);
}

/// @notice Minimal Uniswap V2 LP interface.
interface IUniswapV2Minimal {
    function token0() external view returns (address);
    
    function token1() external view returns (address);
    
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

/// @notice Migrator for UniswapV2-type pair pools and Trident.
contract TridentSushiRoll {
    address internal immutable tridentRouter;

    constructor(address _tridentRouter) {
        tridentRouter = _tridentRouter;
    }
    
    /// @notice Migrates UniswapV2-type liquidity to Trident.
    /// @param pair UniswapV2-type pair to migrate from.
    /// @param _liquidity UniswapV2-type liquidity to migrate.
    /// @param pool Pool address to add liquidity to.
    /// @param minLiquidity Minimum output liquidity - caps slippage.
    /// @param data Data required by the pool to add liquidity.
    function migrateFromUniswapV2toTrident(
        address pair, 
        uint256 _liquidity,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) external returns (uint256 liquidity) {
        IERC20(pair).transferFrom(msg.sender, address(pair), _liquidity);
        
        IUniswapV2Minimal(pair).burn(address(this));

        ITridentRouterMinimal.TokenInput[] memory input = new ITridentRouterMinimal.TokenInput[](2);
        
        IERC20 token0 = IERC20(IUniswapV2Minimal(pair).token0());
        IERC20 token1 = IERC20(IUniswapV2Minimal(pair).token1());
        
        input[0].token = address(token0);
        input[0].native = true;
        input[0].amount = token0.balanceOf(address(this));
        
        input[1].token = address(token1);
        input[1].native = true;
        input[1].amount = token1.balanceOf(address(this));

        token0.approve(tridentRouter, input[0].amount);
        token1.approve(tridentRouter, input[1].amount);
        
        liquidity = ITridentRouterMinimal(tridentRouter).addLiquidity(
            input,
            pool,
            minLiquidity,
            data
        );
    }
}

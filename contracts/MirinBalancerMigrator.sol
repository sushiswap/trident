// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import "./libraries/MirinLibrary.sol";
import "./libraries/SafeERC20.sol";

interface IBFactory {
    function isBPool(address b) external view returns (bool);
}

interface IBPool {
    function getNumTokens() external view returns (uint256);

    function getCurrentTokens() external view returns (address[] memory tokens);

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;
}

contract MirinBalancerMigrator {
    using SafeERC20 for IERC20;

    address public immutable bFactory;
    address public immutable factory;
    address public immutable legacyFactory;
    address public immutable weth;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        _;
    }

    constructor(
        address _factory,
        address _legacyFactory,
        address _bFactory,
        address _weth
    ) {
        bFactory = _bFactory;
        factory = _factory;
        legacyFactory = _legacyFactory;
        weth = _weth;
    }

    function migrate(
        address pool,
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 amountToRemove,
        uint256 liquidityMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) {
        require(IBFactory(bFactory).isBPool(pool), "MIRIN: INVALID_POOL");
        require(IBPool(pool).getNumTokens() == 2, "MIRIN: TOO_MANY_TOKENS");

        address[] memory tokens = IBPool(pool).getCurrentTokens();
        require(
            (tokens[0] == tokenA && tokens[1] == tokenB) || (tokens[0] == tokenB && tokens[1] == tokenA),
            "MIRIN: INVALID_TOKENS"
        );

        IERC20(pool).safeTransferFrom(msg.sender, address(this), amountToRemove);
        IBPool(pool).exitPool(amountToRemove, new uint256[](2));

        uint256 amountA = IERC20(tokenA).balanceOf(address(this));
        uint256 amountB = IERC20(tokenB).balanceOf(address(this));
        _addLiquidity(tokenA, tokenB, pid, amountA, amountB, liquidityMin, to);
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidityMin,
        address to
    ) internal returns (uint256 liquidity) {
        address pool = MirinLibrary.getPool(factory, legacyFactory, tokenA, tokenB, pid);
        IERC20(tokenA).safeTransferFrom(msg.sender, pool, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pool, amountB);
        liquidity = IMirinPool(pool).mint(to);
        require(liquidity >= liquidityMin, "MIRIN: INSUFFICIENT_LIQUIDITY");
    }
}

// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinHelpers.sol";

interface IBFactory {
    function isBPool(address b) external view returns (bool);
}

interface IBPool {
    function getNumTokens() external view returns (uint256);

    function getCurrentTokens() external view returns (address[] memory tokens);

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;
}

contract MirinBalancerMigrator is MirinHelpers {
    address public immutable bFactory;

    constructor(
        address _factory,
        address _legacyFactory,
        address _bFactory,
        address _weth
    ) MirinHelpers(_factory, _legacyFactory, _weth) {
        bFactory = _bFactory;
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

        _safeTransferFrom(pool, msg.sender, address(this), amountToRemove);
        IBPool(pool).exitPool(amountToRemove, new uint256[](2));

        uint256 amountA = IERC20(tokenA).balanceOf(address(this));
        uint256 amountB = IERC20(tokenB).balanceOf(address(this));
        _addLiquidity(tokenA, tokenB, pid, amountA, amountB, liquidityMin, to);
    }
}

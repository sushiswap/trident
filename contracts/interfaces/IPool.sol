// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

interface IPool {
    struct liquidityInput {
        address token;
        bool native;
        uint256 amountDesired;
        uint256 amountMin;
    }

    struct liquidityInputOptimal {
        address token;
        bool native;
        uint256 amount;
    }

    struct liquidityAmount {
        address token;
        uint256 amount;
    }

    function swapWithoutContext(
        address tokenIn,
        address tokenOut,
        address recipient,
        bool unwrapBento
    ) external returns (uint256 finalAmountOut);

    function swapWithContext(
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        bool unwrapBento,
        uint256 amountIn
    ) external returns (uint256 finalAmountOut);

    function getOptimalLiquidityInAmounts(liquidityInput[] calldata liquidityInputs)
        external
        returns (liquidityAmount[] memory liquidityOptimal);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to, bool unwrapBento) external returns (liquidityAmount[] memory withdrawnAmounts);

    function burnLiquiditySingle(address tokenOut, address to, bool unwrapBento) external returns (uint256 amount);
}

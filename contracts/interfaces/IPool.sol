// SPDX-License-Identifier: MIT

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

    function swap(
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        uint256 amountIn,
        uint256 amountOut
    ) external returns(uint256 finalAmountOut);

    function getOptimalLiquidityInAmounts(
        liquidityInput[] calldata liquidityInputs
    ) external returns(liquidityAmount[] memory liquidityOptimal);

    function mint(address to) external returns (uint256 liquidity);
}

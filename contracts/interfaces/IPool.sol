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
        uint256 amount
    ) external returns(uint256 oppositeSideAmount);

    function getOptimalLiquidityInAmounts(
        liquidityInput[] calldata liquidityInputs
    ) external returns(liquidityAmount[] memory liquidityOptimal);

    function mint(address to) external returns (uint256 liquidity);
    function burnLiquiditySingle(address tokenOut, address to) external returns (uint256 amount);
}

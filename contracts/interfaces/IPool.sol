// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

/// @notice Trident exchange pool interface.
interface IPool {
    event Swap(
        address indexed recipient,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

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

    function mint(bytes calldata mintData) external returns (uint256 liquidity);

    function burn(bytes calldata burnData) external returns (liquidityAmount[] memory withdrawnAmounts);

    function burnLiquiditySingle(bytes calldata burnData) external returns (uint256 amount);

    function poolType() external pure returns (uint256);

    function assets(uint256 index) external view returns (address);

    function assetsCount() external view returns (uint256);
}

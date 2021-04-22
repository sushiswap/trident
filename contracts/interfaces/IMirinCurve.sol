// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface IMirinCurve {
    function canUpdateData(bytes32 oldData, bytes32 newData) external pure returns (bool);

    function isValidData(bytes32 data) external pure returns (bool);

    function computeLiquidity(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) external view returns (uint256);

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external view returns (uint256);

    function computeAmountOut(
        uint256 amountIn,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view returns (uint256);

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view returns (uint256);
}

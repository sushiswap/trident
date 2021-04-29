// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface IMirinTwapOracle {
    function pairs() external view returns (address[] memory);

    function current(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint256 amountOut);

    function quote(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 granularity
    ) external view returns (uint256 amountOut);
}

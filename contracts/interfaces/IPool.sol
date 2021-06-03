// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface IPool {
    function swap(
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        uint256 amount
    ) external returns(uint256 oppositeSideAmount);
}

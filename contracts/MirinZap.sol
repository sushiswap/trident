// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinHelpers.sol";

contract MirinZapper is MirinHelpers {
    constructor(address _FACTORY, address _WETH) MirinHelpers(_FACTORY, _WETH) {}

    function zapIn(
        uint256 swapAmountA,
        address[] calldata swapPath,
        uint256[] calldata swapPids,
        uint256 liquidityAmountA,
        uint256 liquidityAmountAMin,
        uint256 liquidityAmountBMin,
        uint256 liquidityPid,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        uint256[] memory amounts = _swapExactTokensForTokens(swapAmountA, 0, swapPath, swapPids, address(this));
        uint256 length = amounts.length;
        _addLiquidity(
            swapPath[0],
            swapPath[length - 1],
            liquidityPid,
            liquidityAmountA,
            amounts[length - 1],
            liquidityAmountAMin,
            liquidityAmountBMin,
            to
        );
    }

    function zapInETH(
        address[] calldata swapPath,
        uint256[] calldata swapPids,
        uint256 liquidityAmountA,
        uint256 liquidityAmountAMin,
        uint256 liquidityAmountBMin,
        uint256 liquidityPid,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        uint256[] memory amounts = _swapExactETHForTokens(0, swapPath, swapPids, address(this));
        uint256 length = amounts.length;
        _addLiquidity(
            swapPath[0],
            swapPath[length - 1],
            liquidityPid,
            liquidityAmountA,
            amounts[length - 1],
            liquidityAmountAMin,
            liquidityAmountBMin,
            to
        );
    }

    function zapOut(
        address tokenA,
        address tokenB,
        uint256 liquidityPid,
        uint256 liquidityAmount,
        uint256 amountOutMin,
        address[] calldata swapPath,
        uint256[] calldata swapPids,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        (uint256 amountA, uint256 amountB) =
            _removeLiquidity(tokenA, tokenB, liquidityPid, liquidityAmount, 0, 0, address(this));
        if (swapPath[0] == tokenA && swapPath[swapPath.length - 1] == tokenB) {
            uint256 balance = IERC20(tokenB).balanceOf(address(this));
            _swapExactTokensForTokens(amountA, amountOutMin - balance, swapPath, swapPids, to);
            _safeTransfer(tokenB, to, balance);
        } else if (swapPath[0] == tokenB && swapPath[swapPath.length - 1] == tokenA) {
            uint256 balance = IERC20(tokenA).balanceOf(address(this));
            _swapExactTokensForTokens(amountB, amountOutMin - balance, swapPath, swapPids, to);
            _safeTransfer(tokenA, to, balance);
        } else {
            revert("MIRIN: INCORRECT_PATH");
        }
    }

    function zapOutETH(
        address token,
        uint256 liquidityPid,
        uint256 liquidityAmount,
        uint256 amountOutMin,
        address[] calldata swapPath,
        uint256[] calldata swapPids,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        (uint256 amountToken, ) = _removeLiquidityETH(token, liquidityPid, liquidityAmount, 0, 0, address(this));
        uint256 balance = address(this).balance;
        _swapExactTokensForETH(amountToken, amountOutMin - balance, swapPath, swapPids, to);
        _safeTransferETH(to, balance);
    }
}

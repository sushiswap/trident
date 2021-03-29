// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinHelpers.sol";
import "./interfaces/IWETH.sol";

contract MirinRouter is MirinHelpers {
    constructor(
        address _factory,
        address _legacyFactory,
        address _weth
    ) MirinHelpers(_factory, _legacyFactory, _weth) {}

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        return _swapExactTokensForTokens(amountIn, amountOutMin, path, pids, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256[] calldata pids,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = _getAmountsIn(amountOut, path, pids);
        require(amounts[0] <= amountInMax, "MIRIN: EXCESSIVE_INPUT_AMOUNT");
        _safeTransferFrom(path[0], msg.sender, _getPool(path[0], path[1], pids[0]), amounts[0]);
        _swap(amounts, path, pids, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        return _swapExactETHForTokens(amountOutMin, path, pids, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256[] calldata pids,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == weth, "MIRIN: INVALID_PATH");
        amounts = _getAmountsIn(amountOut, path, pids);
        require(amounts[0] <= amountInMax, "MIRIN: EXCESSIVE_INPUT_AMOUNT");
        _safeTransferFrom(path[0], msg.sender, _getPool(path[0], path[1], pids[0]), amounts[0]);
        _swap(amounts, path, pids, address(this));
        IWETH(weth).withdraw(amounts[amounts.length - 1]);
        _safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        return _swapExactTokensForETH(amountIn, amountOutMin, path, pids, to);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        uint256[] calldata pids,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == weth, "MIRIN: INVALID_PATH");
        amounts = _getAmountsIn(amountOut, path, pids);
        require(amounts[0] <= msg.value, "MIRIN: EXCESSIVE_INPUT_AMOUNT");
        IWETH(weth).deposit{value: amounts[0]}();
        assert(IWETH(weth).transfer(_getPool(path[0], path[1], pids[0]), amounts[0]));
        _swap(amounts, path, pids, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) _safeTransferETH(msg.sender, msg.value - amounts[0]);
    }
}

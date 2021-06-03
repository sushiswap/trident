// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./interfaces/IWETH.sol";
import "./interfaces/IMirinPool.sol";
import "./interfaces/IMirinCurve.sol";
import "./libraries/MirinLibrary.sol";
import "./libraries/SafeERC20.sol";

contract MirinRouter {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable legacyFactory;
    address public immutable weth;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        _;
    }

    constructor(
        address _factory,
        address _legacyFactory,
        address _weth
    ) {
        factory = _factory;
        legacyFactory = _legacyFactory;
        weth = _weth;
    }

    receive() external payable {
        assert(msg.sender == weth); // only accept ETH via fallback from the weth contract
    }

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
        amounts = MirinLibrary.getAmountsIn(factory, legacyFactory, amountOut, path, pids);
        require(amounts[0] <= amountInMax, "MIRIN: EXCESSIVE_INPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            MirinLibrary.getPool(factory, legacyFactory, path[0], path[1], pids[0]),
            amounts[0]
        );
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
        amounts = MirinLibrary.getAmountsIn(factory, legacyFactory, amountOut, path, pids);
        require(amounts[0] <= amountInMax, "MIRIN: EXCESSIVE_INPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            MirinLibrary.getPool(factory, legacyFactory, path[0], path[1], pids[0]),
            amounts[0]
        );
        _swap(amounts, path, pids, address(this));
        IWETH(weth).withdraw(amounts[amounts.length - 1]);
        MirinLibrary.safeTransferETH(to, amounts[amounts.length - 1]);
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
        amounts = MirinLibrary.getAmountsIn(factory, legacyFactory, amountOut, path, pids);
        require(amounts[0] <= msg.value, "MIRIN: EXCESSIVE_INPUT_AMOUNT");
        IWETH(weth).deposit{value: amounts[0]}();
        assert(
            IWETH(weth).transfer(MirinLibrary.getPool(factory, legacyFactory, path[0], path[1], pids[0]), amounts[0])
        );
        _swap(amounts, path, pids, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) MirinLibrary.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to
    ) internal returns (uint256[] memory amounts) {
        amounts = MirinLibrary.getAmountsOut(factory, legacyFactory, amountIn, path, pids);
        require(amounts[amounts.length - 1] >= amountOutMin, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            MirinLibrary.getPool(factory, legacyFactory, path[0], path[1], pids[0]),
            amounts[0]
        );
        _swap(amounts, path, pids, to);
    }

    function _swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to
    ) internal returns (uint256[] memory amounts) {
        require(path[0] == weth, "MIRIN: INVALID_PATH");
        amounts = MirinLibrary.getAmountsOut(factory, legacyFactory, msg.value, path, pids);
        require(amounts[amounts.length - 1] >= amountOutMin, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(weth).deposit{value: amounts[0]}();
        assert(
            IWETH(weth).transfer(MirinLibrary.getPool(factory, legacyFactory, path[0], path[1], pids[0]), amounts[0])
        );
        _swap(amounts, path, pids, to);
    }

    function _swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to
    ) internal returns (uint256[] memory amounts) {
        require(path[path.length - 1] == weth, "MIRIN: INVALID_PATH");
        amounts = MirinLibrary.getAmountsOut(factory, legacyFactory, amountIn, path, pids);
        require(amounts[amounts.length - 1] >= amountOutMin, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            MirinLibrary.getPool(factory, legacyFactory, path[0], path[1], pids[0]),
            amounts[0]
        );
        _swap(amounts, path, pids, address(this));
        IWETH(weth).withdraw(amounts[amounts.length - 1]);
        MirinLibrary.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        uint256[] memory pids,
        address _to
    ) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = MirinLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to =
                i < path.length - 2
                    ? MirinLibrary.getPool(factory, legacyFactory, output, path[i + 2], pids[i + 1])
                    : _to;
            IMirinPool(MirinLibrary.getPool(factory, legacyFactory, input, output, pids[i])).swap(
                amount0Out,
                amount1Out,
                to,
                bytes("")
            );
        }
    }
}

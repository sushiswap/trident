// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinHelpers.sol";

contract MirinLiquidityManager is MirinHelpers {
    struct AddLiquidityParams {
        address tokenA;
        address tokenB;
        uint256 pid;
        uint256 amountA;
        uint256 amountB;
        uint256 liquidityMin;
    }

    struct AddLiquidityETHParams {
        address token;
        uint256 pid;
        uint256 amountToken;
        uint256 amountETH;
        uint256 liquidityMin;
    }

    struct RemoveLiquidityParams {
        address tokenA;
        address tokenB;
        uint256 pid;
        uint256 liquidity;
        uint256 amountAMin;
        uint256 amountBMin;
    }

    struct RemoveLiquidityETHParams {
        address token;
        uint256 pid;
        uint256 liquidity;
        uint256 amountTokenMin;
        uint256 amountETHMin;
    }

    modifier onlyOperator(
        address tokenA,
        address tokenB,
        uint256 pid
    ) {
        _;
    }

    constructor(address _FACTORY, address _WETH) MirinHelpers(_FACTORY, _WETH) {}

    function addLiquidityMultiple(
        AddLiquidityParams[] calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        for (uint256 i; i < params.length; i++) {
            _addLiquidity(
                params[i].tokenA,
                params[i].tokenB,
                params[i].pid,
                params[i].amountA,
                params[i].amountB,
                params[i].liquidityMin,
                to
            );
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidityMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 liquidity) {
        return _addLiquidity(tokenA, tokenB, pid, amountA, amountB, liquidityMin, to);
    }

    function addLiquidityETHMultiple(
        AddLiquidityETHParams[] calldata params,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        for (uint256 i; i < params.length; i++) {
            _addLiquidityETH(
                params[i].token,
                params[i].pid,
                params[i].amountToken,
                params[i].amountETH,
                params[i].liquidityMin,
                to
            );
        }
    }

    function addLiquidityETH(
        address token,
        uint256 pid,
        uint256 amountToken,
        uint256 liquidityMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 liquidity) {
        return _addLiquidityETH(token, pid, amountToken, msg.value, liquidityMin, to);
    }

    function removeLiquidityMultiple(
        RemoveLiquidityParams[] calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        for (uint256 i; i < params.length; i++) {
            _removeLiquidity(
                params[i].tokenA,
                params[i].tokenB,
                params[i].pid,
                params[i].liquidity,
                params[i].amountAMin,
                params[i].amountBMin,
                to
            );
        }
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        return _removeLiquidity(tokenA, tokenB, pid, liquidity, amountAMin, amountBMin, to);
    }

    function removeLiquidityETHMultiple(
        RemoveLiquidityETHParams[] calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        for (uint256 i; i < params.length; i++) {
            _removeLiquidityETH(
                params[i].token,
                params[i].pid,
                params[i].liquidity,
                params[i].amountTokenMin,
                params[i].amountETHMin,
                to
            );
        }
    }

    function removeLiquidityETH(
        address token,
        uint256 pid,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        return _removeLiquidityETH(token, pid, liquidity, amountTokenMin, amountETHMin, to);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        MirinPool(_getPool(tokenA, tokenB, pid)).permit(
            msg.sender,
            address(this),
            approveMax ? type(uint256).max : liquidity,
            deadline,
            v,
            r,
            s
        );
        (amountA, amountB) = _removeLiquidity(tokenA, tokenB, pid, liquidity, amountAMin, amountBMin, to);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 pid,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH) {
        MirinPool(_getPool(token, WETH, pid)).permit(
            msg.sender,
            address(this),
            approveMax ? type(uint256).max : liquidity,
            deadline,
            v,
            r,
            s
        );
        (amountToken, amountETH) = _removeLiquidityETH(token, pid, liquidity, amountTokenMin, amountETHMin, to);
    }
}

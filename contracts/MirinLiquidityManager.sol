// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./interfaces/IWETH.sol";
import "./libraries/MirinLibrary.sol";
import "./libraries/TransferHelper.sol";

contract MirinLiquidityManager {
    using TransferHelper for IERC20;

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

    function addLiquidityMultiple(
        AddLiquidityParams[] calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        for (uint256 i; i < params.length; i++) {
            _addLiquidity(params[i], to);
        }
    }

    function addLiquidity(
        AddLiquidityParams calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 liquidity) {
        return _addLiquidity(params, to);
    }

    function addLiquidityETHMultiple(
        AddLiquidityETHParams[] calldata params,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        for (uint256 i; i < params.length; i++) {
            _addLiquidityETH(params[i], to);
        }
    }

    function addLiquidityETH(
        AddLiquidityETHParams calldata params,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 liquidity) {
        return _addLiquidityETH(params, to);
    }

    function removeLiquidityMultiple(
        RemoveLiquidityParams[] calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        for (uint256 i; i < params.length; i++) {
            _removeLiquidity(params[i], to);
        }
    }

    function removeLiquidity(
        RemoveLiquidityParams calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        return _removeLiquidity(params, to);
    }

    function removeLiquidityETHMultiple(
        RemoveLiquidityETHParams[] calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        for (uint256 i; i < params.length; i++) {
            _removeLiquidityETH(params[i], to);
        }
    }

    function removeLiquidityETH(
        RemoveLiquidityETHParams calldata params,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        return _removeLiquidityETH(params, to);
    }

    function removeLiquidityWithPermit(
        RemoveLiquidityParams calldata params,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        IMirinPool(MirinLibrary.getPool(factory, legacyFactory, params.tokenA, params.tokenB, params.pid)).permit(
            msg.sender,
            address(this),
            approveMax ? type(uint256).max : params.liquidity,
            deadline,
            v,
            r,
            s
        );
        (amountA, amountB) = _removeLiquidity(params, to);
    }

    function removeLiquidityETHWithPermit(
        RemoveLiquidityETHParams calldata params,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH) {
        IMirinPool(MirinLibrary.getPool(factory, legacyFactory, params.token, weth, params.pid)).permit(
            msg.sender,
            address(this),
            approveMax ? type(uint256).max : params.liquidity,
            deadline,
            v,
            r,
            s
        );
        (amountToken, amountETH) = _removeLiquidityETH(params, to);
    }

    function _addLiquidity(AddLiquidityParams memory params, address to) internal returns (uint256 liquidity) {
        address pool = MirinLibrary.getPool(factory, legacyFactory, params.tokenA, params.tokenB, params.pid);
        IERC20(params.tokenA).safeTransferFrom(msg.sender, pool, params.amountA);
        IERC20(params.tokenB).safeTransferFrom(msg.sender, pool, params.amountB);
        liquidity = IMirinPool(pool).mint(to);
        require(liquidity >= params.liquidityMin, "MIRIN: INSUFFICIENT_LIQUIDITY");
    }

    function _addLiquidityETH(AddLiquidityETHParams memory params, address to) internal returns (uint256 liquidity) {
        address pool = MirinLibrary.getPool(factory, legacyFactory, params.token, weth, params.pid);
        IERC20(params.token).safeTransferFrom(msg.sender, pool, params.amountToken);
        IWETH(weth).deposit{value: params.amountETH}();
        assert(IWETH(weth).transfer(pool, params.amountETH));
        liquidity = IMirinPool(pool).mint(to);
        require(liquidity >= params.liquidityMin, "MIRIN: INSUFFICIENT_LIQUIDITY");
    }

    function _removeLiquidity(RemoveLiquidityParams memory params, address to)
        internal
        returns (uint256 amountA, uint256 amountB)
    {
        address pool = MirinLibrary.getPool(factory, legacyFactory, params.tokenA, params.tokenB, params.pid);
        IMirinPool(pool).transferFrom(msg.sender, pool, params.liquidity);
        (uint256 amount0, uint256 amount1) = IMirinPool(pool).burn(to);
        (address token0, ) = MirinLibrary.sortTokens(params.tokenA, params.tokenB);
        (amountA, amountB) = params.tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= params.amountAMin, "MIRIN: INSUFFICIENT_A_AMOUNT");
        require(amountB >= params.amountBMin, "MIRIN: INSUFFICIENT_B_AMOUNT");
    }

    function _removeLiquidityETH(RemoveLiquidityETHParams memory params, address to)
        internal
        returns (uint256 amountToken, uint256 amountETH)
    {
        address pool = MirinLibrary.getPool(factory, legacyFactory, params.token, weth, params.pid);
        IMirinPool(pool).transferFrom(msg.sender, pool, params.liquidity);
        (uint256 amount0, uint256 amount1) = IMirinPool(pool).burn(to);
        (address token0, ) = MirinLibrary.sortTokens(params.token, weth);
        (amountToken, amountETH) = params.token == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountToken >= params.amountTokenMin, "MIRIN: INSUFFICIENT_TOKEN_AMOUNT");
        require(amountETH >= params.amountETHMin, "MIRIN: INSUFFICIENT_ETH_AMOUNT");
        IERC20(params.token).safeTransfer(to, amountToken);
        IWETH(weth).withdraw(amountETH);
        MirinLibrary.safeTransferETH(to, amountETH);
    }
}

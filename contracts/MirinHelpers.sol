// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinFactory.sol";
import "./interfaces/IWETH.sol";

contract MirinHelpers {
    address public immutable FACTORY;
    address public immutable WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        _;
    }

    constructor(address _FACTORY, address _WETH) {
        FACTORY = _FACTORY;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to
    ) internal returns (uint256[] memory amounts) {
        amounts = _getAmountsOut(amountIn, path, pids);
        require(amounts[amounts.length - 1] >= amountOutMin, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        _safeTransferFrom(path[0], msg.sender, _getPool(path[0], path[1], pids[0]), amounts[0]);
        _swap(amounts, path, pids, to);
    }

    function _swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to
    ) internal returns (uint256[] memory amounts) {
        require(path[0] == WETH, "MIRIN: INVALID_PATH");
        amounts = _getAmountsOut(msg.value, path, pids);
        require(amounts[amounts.length - 1] >= amountOutMin, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(_getPool(path[0], path[1], pids[0]), amounts[0]));
        _swap(amounts, path, pids, to);
    }

    function _swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256[] calldata pids,
        address to
    ) internal returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "MIRIN: INVALID_PATH");
        amounts = _getAmountsOut(amountIn, path, pids);
        require(amounts[amounts.length - 1] >= amountOutMin, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        _safeTransferFrom(path[0], msg.sender, _getPool(path[0], path[1], pids[0]), amounts[0]);
        _swap(amounts, path, pids, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        _safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        uint256[] memory pids,
        address _to
    ) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? _getPool(output, path[i + 2], pids[i + 1]) : _to;
            MirinPool(_getPool(input, output, pids[i])).swap(amount0Out, amount1Out, to);
        }
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidityMin,
        address to
    ) internal returns (uint256 liquidity) {
        address pool = _getPool(tokenA, tokenB, pid);
        _safeTransferFrom(tokenA, msg.sender, pool, amountA);
        _safeTransferFrom(tokenB, msg.sender, pool, amountB);
        liquidity = MirinPool(pool).mint(to);
        require(liquidity >= liquidityMin, "MIRIN: INSUFFICIENT_LIQUIDITY");
    }

    function _addLiquidityETH(
        address token,
        uint256 pid,
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidityMin,
        address to
    ) internal returns (uint256 liquidity) {
        address pool = _getPool(token, WETH, pid);
        _safeTransferFrom(token, msg.sender, pool, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pool, amountETH));
        liquidity = MirinPool(pool).mint(to);
        require(liquidity >= liquidityMin, "MIRIN: INSUFFICIENT_LIQUIDITY");
    }

    function _removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) internal returns (uint256 amountA, uint256 amountB) {
        address pool = _getPool(tokenA, tokenB, pid);
        MirinPool(pool).transferFrom(msg.sender, pool, liquidity);
        (uint256 amount0, uint256 amount1) = MirinPool(pool).burn(0, 0, to);
        (address token0, ) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "MIRIN: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "MIRIN: INSUFFICIENT_B_AMOUNT");
    }

    function _removeLiquidityETH(
        address token,
        uint256 pid,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to
    ) internal returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = _removeLiquidity(
            token,
            WETH,
            pid,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this)
        );
        _safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        _safeTransferETH(to, amountETH);
    }

    function _getPool(
        address tokenA,
        address tokenB,
        uint256 pid
    ) internal view returns (address pool) {
        pool = MirinFactory(FACTORY).getPool(tokenA, tokenB, pid);
    }

    function _getPoolInfo(address pool, address tokenA)
        internal
        view
        returns (
            uint256 reserveA,
            uint256 reserveB,
            uint8 weightA,
            uint8 weightB
        )
    {
        address token0 = MirinPool(pool).TOKEN0();
        (uint256 reserve0, uint256 reserve1, ) = MirinPool(pool).getReserves();
        (uint8 weight0, uint8 weight1) = MirinPool(pool).getWeights();
        (reserveA, reserveB, weightA, weightB) = tokenA == token0
            ? (reserve0, reserve1, weight0, weight1)
            : (reserve1, reserve0, weight1, weight0);
    }

    function _getAmountsOut(
        uint256 amountIn,
        address[] memory path,
        uint256[] memory pids
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "MIRIN: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            address tokenA = path[i];
            address pool = _getPool(tokenA, path[i + 1], pids[i]);
            (uint256 reserveIn, uint256 reserveOut, uint8 weightIn, uint8 weightOut) = _getPoolInfo(pool, tokenA);
            amounts[i + 1] = _getAmountOut(
                amounts[i],
                reserveIn,
                reserveOut,
                weightIn,
                weightOut,
                MirinPool(pool).swapFee()
            );
        }
    }

    function _getAmountsIn(
        uint256 amountOut,
        address[] memory path,
        uint256[] memory pids
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "MIRIN: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            address tokenA = path[i - 1];
            address pool = _getPool(tokenA, path[i], pids[i - 1]);
            (uint256 reserveIn, uint256 reserveOut, uint8 weightIn, uint8 weightOut) = _getPoolInfo(pool, tokenA);
            amounts[i - 1] = _getAmountIn(
                amounts[i],
                reserveIn,
                reserveOut,
                weightIn,
                weightOut,
                MirinPool(pool).swapFee()
            );
        }
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint8 weightIn,
        uint8 weightOut,
        uint8 swapFee
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * (1000 - swapFee);
        uint256 numerator = amountInWithFee * reserveOut * weightIn;
        uint256 denominator = reserveIn * weightOut * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint8 weightIn,
        uint8 weightOut,
        uint8 swapFee
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * weightOut * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * weightIn * (1000 - swapFee);
        amountIn = (numerator / denominator) + 1;
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "MIRIN: ZERO_ADDRESS");
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "MIRIN: ETH_TRANSFER_FAILED");
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "MIRIN: TRANSFER_FAILED");
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "MIRIN: TRANSFER_FROM_FAILED");
    }
}

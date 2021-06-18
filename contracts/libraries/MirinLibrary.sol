// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../interfaces/IMirinFactory.sol";
import "../interfaces/IMirinCurve.sol";

library MirinLibrary {
    uint256 public constant LEGACY_POOL_INDEX = type(uint256).max;
    uint256 public constant FRANCHISED_POOL_INDEX_0 = 2**255;

    function getPool(
        address factory,
        address legacyFactory,
        address tokenA,
        address tokenB,
        uint256 pid
    ) internal view returns (address pool) {
        if (pid == LEGACY_POOL_INDEX) {
            (address token0, address token1) = sortTokens(tokenA, tokenB);
            pool = address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                legacyFactory,
                                keccak256(abi.encodePacked(token0, token1)),
                                hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303" // init code hash
                            )
                        )
                    )
                )
            );
        } else if (pid >= FRANCHISED_POOL_INDEX_0) {
            pool = IMirinFactory(factory).getFranchisedPool(tokenA, tokenB, pid - FRANCHISED_POOL_INDEX_0);
        } else {
            pool = IMirinFactory(factory).getPublicPool(tokenA, tokenB, pid);
        }
    }

    function getAmountsOut(
        address factory,
        address legacyFactory,
        uint256 amountIn,
        address[] memory path,
        uint256[] memory pids
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "MIRIN: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            address tokenA = path[i];
            uint256 pid = pids[i];
            address pool = getPool(factory, legacyFactory, tokenA, path[i + 1], pid);
            address token0 = IMirinPool(pool).token0();
            (uint112 reserve0, uint112 reserve1, ) = IMirinPool(pool).getReserves();
            if (pid == LEGACY_POOL_INDEX) {
                (uint256 reserveIn, uint256 reserveOut) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
            } else {
                address curve = IMirinPool(pool).curve();
                amounts[i + 1] = IMirinCurve(curve).computeAmountOut(
                    amounts[i],
                    reserve0,
                    reserve1,
                    IMirinPool(pool).curveData(),
                    IMirinPool(pool).swapFee(),
                    tokenA == token0 ? 0 : 1
                );
            }
        }
    }

    function getAmountsIn(
        address factory,
        address legacyFactory,
        uint256 amountOut,
        address[] memory path,
        uint256[] memory pids
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "MIRIN: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            address tokenA = path[i - 1];
            uint256 pid = pids[i - 1];
            address pool = getPool(factory, legacyFactory, tokenA, path[i], pid);
            address token0 = IMirinPool(pool).token0();
            (uint112 reserve0, uint112 reserve1, ) = IMirinPool(pool).getReserves();
            if (pid == LEGACY_POOL_INDEX) {
                (uint256 reserveIn, uint256 reserveOut) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amounts[i - 1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
            } else {
                address curve = IMirinPool(pool).curve();
                amounts[i + 1] = IMirinCurve(curve).computeAmountIn(
                    amounts[i],
                    reserve0,
                    reserve1,
                    IMirinPool(pool).curveData(),
                    IMirinPool(pool).swapFee(),
                    tokenA == token0 ? 0 : 1
                );
            }
        }
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) private pure returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * (1000 - 3);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) private pure returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * (1000 - 3);
        amountIn = (numerator / denominator) + 1;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "MIRIN: ZERO_ADDRESS");
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "MIRIN: ETH_TRANSFER_FAILED");
    }
}

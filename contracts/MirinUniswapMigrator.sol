// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinHelpers.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract MirinUniswapMigrator is MirinHelpers {
    address public immutable UNISWAP_FACTORY;

    constructor(
        address _FACTORY,
        address _WETH,
        address _UNISWAP_FACTORY
    ) MirinHelpers(_FACTORY, _WETH) {
        UNISWAP_FACTORY = _UNISWAP_FACTORY;
    }

    function migrateFromUniswapWithPermit(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 liquidity,
        uint256 liquidityMin,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IUniswapV2Pair pair = IUniswapV2Pair(_pairFor(tokenA, tokenB));
        pair.permit(msg.sender, address(this), liquidity, deadline, v, r, s);
        migrateFromUniswap(tokenA, tokenB, pid, liquidity, liquidityMin, to, deadline);
    }

    function _pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            UNISWAP_FACTORY,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
    }

    function migrateFromUniswap(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 liquidity,
        uint256 liquidityMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) {
        (uint256 amountA, uint256 amountB) = _removeLiquidityFromUniswap(tokenA, tokenB, liquidity);
        _addLiquidity(tokenA, tokenB, pid, amountA, amountB, liquidityMin, to);
    }

    function _removeLiquidityFromUniswap(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) internal returns (uint256 amountA, uint256 amountB) {
        IUniswapV2Pair pair = IUniswapV2Pair(_pairFor(tokenA, tokenB));
        _safeTransferFrom(address(pair), msg.sender, address(pair), liquidity);
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        (address token0, ) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./interfaces/IUniswapV2Pair.sol";
import "./libraries/MirinLibrary.sol";
import "./libraries/SafeERC20.sol";

contract MirinUniswapMigrator {
    using SafeERC20 for IERC20;

    address public immutable uniswapFactory;
    address public immutable factory;
    address public immutable legacyFactory;
    address public immutable weth;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        _;
    }

    constructor(
        address _uniswapFactory,
        address _factory,
        address _legacyFactory,
        address _weth
    ) {
        uniswapFactory = _uniswapFactory;
        factory = _factory;
        legacyFactory = _legacyFactory;
        weth = _weth;
    }

    function migrateWithPermit(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 amountToRemove,
        uint256 liquidityMin,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IUniswapV2Pair pair = IUniswapV2Pair(_pairFor(tokenA, tokenB));
        pair.permit(msg.sender, address(this), amountToRemove, deadline, v, r, s);
        migrate(tokenA, tokenB, pid, amountToRemove, liquidityMin, to, deadline);
    }

    function migrate(
        address tokenA,
        address tokenB,
        uint256 pid,
        uint256 amountToRemove,
        uint256 liquidityMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) {
        (uint256 amountA, uint256 amountB) = _removeLiquidityFromUniswap(tokenA, tokenB, amountToRemove);
        _addLiquidity(tokenA, tokenB, pid, amountA, amountB, liquidityMin, to);
    }

    function _removeLiquidityFromUniswap(
        address tokenA,
        address tokenB,
        uint256 amountToRemove
    ) internal returns (uint256 amountA, uint256 amountB) {
        address pair = _pairFor(tokenA, tokenB);
        IERC20(pair).safeTransferFrom(msg.sender, pair, amountToRemove);
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(address(this));
        (address token0, ) = MirinLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    }

    function _pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = MirinLibrary.sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            uniswapFactory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
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
        address pool = MirinLibrary.getPool(factory, legacyFactory, tokenA, tokenB, pid);
        IERC20(tokenA).safeTransferFrom(msg.sender, pool, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pool, amountB);
        liquidity = IMirinPool(pool).mint(to);
        require(liquidity >= liquidityMin, "MIRIN: INSUFFICIENT_LIQUIDITY");
    }
}

// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../../interfaces/IMirinCurve.sol";
import "../../libraries/MirinMath.sol";

/**
 * @dev Constant product curve for tokens with different possible weights (k = r_0 * r_1)
 * @author LevX
 */
contract ConstantProductCurve is IMirinCurve {
    uint8 public constant MAX_SWAP_FEE = 100;
    uint8 private constant PRECISION = 104;

    function canUpdateData(bytes32, bytes32) external pure override returns (bool) {
        return false;
    }

    function isValidData(bytes32 data) public pure override returns (bool) {
        return uint256(data) == 0;
    }

    function computeLiquidity(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) external pure override returns (uint256) {
        return MirinMath.sqrt(reserve0 * reserve1);
    }

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external pure override returns (uint224) {
        return tokenIn == 0 ? (uint224(reserve1) << PRECISION) / reserve0 : (uint224(reserve0) << PRECISION) / reserve1;
    }

    function computeAmountOut(
        uint256 amountIn,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external pure override returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");

        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 amountInWithFee = amountIn * (1000 - swapFee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external pure override returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");

        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * (1000 - swapFee);
        amountIn = (numerator / denominator) + 1;
    }
}

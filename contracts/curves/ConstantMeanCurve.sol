// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../interfaces/IMirinCurve.sol";
import "../libraries/MirinMath.sol";

/**
 * @dev Constant mean curve for tokens with different possible weights (k = r_0^w_0 * r_1^w1)
 * @author LevX
 */
contract ConstantMeanCurve is IMirinCurve {
    using FixedPoint for *;

    uint8 public constant MAX_SWAP_FEE = 100;

    modifier onlyValidData(bytes32 data) {
        require(isValidData(data), "MIRIN: INVALID_DATA");
        _;
    }

    function isValidData(bytes32 data) public pure override returns (bool) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return MirinMath.isPow2(weight0 + weight1);
    }

    function computeK(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) external pure override onlyValidData(data) returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return uint256(reserve0)**weight0 * uint256(reserve1)**weight1;
    }

    function computeLiquidity(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) external pure override onlyValidData(data) returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return MirinMath.root(uint256(reserve0)**weight0 * uint256(reserve1)**weight1, weight0 + weight1);
    }

    function computeLiquidity(uint256 k, bytes32 data) external pure override onlyValidData(data) returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return MirinMath.root(k, weight0 + weight1);
    }

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external pure override onlyValidData(data) returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, tokenIn);
        return
            tokenIn == 0
                ? FixedPoint.encode(reserve1).mul(weight0).div(reserve0).div(weight1)._x
                : FixedPoint.encode(reserve0).mul(weight1).div(reserve1).div(weight0)._x;
    }

    function computeAmountOut(
        uint256 amountIn,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external pure override onlyValidData(data) returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve0 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee < MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        uint256 amountInWithFee = amountIn * (1000 - swapFee);
        uint256 numerator = amountInWithFee * reserveOut * weightIn;
        uint256 denominator = reserveIn * weightOut * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external pure override onlyValidData(data) returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve0 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee < MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 numerator = reserveIn * weightOut * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * weightIn * (1000 - swapFee);
        amountIn = (numerator / denominator) + 1;
    }

    function decodeData(bytes32 data, uint8 tokenIn) public pure returns (uint8 weightIn, uint8 weightOut) {
        uint8 weight0 = uint8(uint256(data) >> 248);
        uint8 weight1 = uint8((uint256(data) >> 240) % (2 ^ 8));
        weightIn = tokenIn == 0 ? weight0 : weight1;
        weightOut = tokenIn == 0 ? weight1 : weight0;
    }
}

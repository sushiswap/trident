// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../MirinMath.sol";
import "../interfaces/IMirinCurve.sol";
import "../libraries/FixedPoint.sol";

/**
 * @dev Constant mean curve for tokens with different possible weights (k = r_0^w_0 * r_1^w1)
 * @author LevX
 */
contract ConstantMeanCurve is IMirinCurve, MirinMath {
    using FixedPoint for *;

    uint8 public constant MAX_SWAP_FEE = 100;
    uint8 public constant WEIGHT_SUM = 100;

    modifier onlyValidData(bytes32 data) {
        require(isValidData(data), "MIRIN: INVALID_DATA");
        _;
    }

    function isValidData(bytes32 data) public view override returns (bool) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return weight0 > 0 && weight1 > 0 && weight0 + weight1 == WEIGHT_SUM;
    }

    function computeK(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) external view override onlyValidData(data) returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return uint256(reserve0)**weight0 * uint256(reserve1)**weight1;
    }

    function computeLiquidity(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) external view override onlyValidData(data) returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        (uint256 result, uint8 precision) =
            power(uint256(reserve0)**weight0 * uint256(reserve1)**weight1, 1, 1, weight0 + weight1);
        return result >> precision;
    }

    function computeLiquidity(uint256 k, bytes32 data) external view override onlyValidData(data) returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        (uint256 result, uint8 precision) = power(k, 1, 1, weight0 + weight1);
        return result >> precision;
    }

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external view override onlyValidData(data) returns (uint256) {
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
    ) external view override onlyValidData(data) returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve0 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee < MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        (uint256 result, uint8 precision) =
            power(reserveIn / (reserveIn + amountIn * (1000 - swapFee), 1, weightIn, weightOut));
        amountOut = reserveOut - (reserveOut * result) / (1 << precision);
    }

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view override onlyValidData(data) returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve0 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee < MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        (uint256 result, uint8 precision) = power(reserveOut / (reserveOut - amountOut), 1, weightOut, weightIn) - 1;
        amountIn = ((reserveIn * result) / (1 << precision) - reserveIn) * (1000 - swapFee);
    }

    function decodeData(bytes32 data, uint8 tokenIn) public pure returns (uint8 weightIn, uint8 weightOut) {
        uint8 weight0 = uint8(uint256(data) >> 248);
        uint8 weight1 = uint8((uint256(data) >> 240) % (2 ^ 8));
        weightIn = tokenIn == 0 ? weight0 : weight1;
        weightOut = tokenIn == 0 ? weight1 : weight0;
    }
}

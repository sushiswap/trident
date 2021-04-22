// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../../MirinMath.sol";
import "../../interfaces/IMirinCurve.sol";
import "../../libraries/FixedPoint.sol";
import "../../libraries/MirinMath2.sol";

/**
 * @dev Constant mean curve for tokens with different possible weights (k = r_0^w_0 * r_1^w1)
 * @author LevX
 */
contract ConstantMeanCurve is IMirinCurve, MirinMath {
    using FixedPoint for *;
    using MirinMath2 for uint256;

    uint8 public constant MAX_SWAP_FEE = 100;
    uint8 public constant WEIGHT_SUM = 10;

    function canUpdateData(bytes32, bytes32) external pure override returns (bool) {
        return false;
    }

    function isValidData(bytes32 data) public pure override returns (bool) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return _isValidData(weight0, weight1);
    }

    function decodeData(bytes32 data, uint8 tokenIn) public pure returns (uint8 weightIn, uint8 weightOut) {
        uint8 weight0 = uint8(uint256(data));
        uint8 weight1 = WEIGHT_SUM - weight0;
        require(_isValidData(weight0, weight1), "MIRIN: INVALID_DATA");
        weightIn = tokenIn == 0 ? weight0 : weight1;
        weightOut = tokenIn == 0 ? weight1 : weight0;
    }

    function _isValidData(uint8 weight0, uint8 weight1) internal pure returns (bool) {
        return weight0 > 0 && weight1 > 0 && weight0 + weight1 == WEIGHT_SUM;
    }

    function computeLiquidity(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) external view override returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return generalExp(ln((weight0 * reserve0 + weight1 * reserve1) * FIXED_1) / (weight0 + weight1), MAX_PRECISION);
    }

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external pure override returns (uint256) {
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
    ) external view override returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee < MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);

        uint256 weightRatio = MirinMath2.roundDiv(uint256(weightIn), uint256(weightOut));
        uint256 adjustedIn = MirinMath2.roundMul(amountIn, MirinMath2.BASE - (uint256(swapFee) * 10**15));
        uint256 base = MirinMath2.roundDiv(uint256(reserveIn), uint256(reserveIn) + adjustedIn);
        uint256 pow = MirinMath2.power(base, weightRatio);
        amountOut = MirinMath2.roundMul(uint256(reserveOut), MirinMath2.BASE - pow);
    }

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view override returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee < MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);

        uint256 weightRatio = MirinMath2.roundDiv(uint256(weightOut), uint256(weightIn));
        uint256 base = MirinMath2.roundDiv(uint256(reserveOut), uint256(reserveOut) - amountOut);
        uint256 pow = MirinMath2.power(base, weightRatio);
        amountIn = (uint256(reserveIn) * (pow - MirinMath2.BASE)) / MirinMath2.BASE - (uint256(swapFee) * 10**15);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../../interfaces/IMirinCurve.sol";
import "../../libraries/MirinMath.sol";

/**
 * @dev Constant mean curve for tokens with different possible weights (k = r_0^w_0 * r_1^w1)
 * @author LevX
 */
contract ConstantMeanCurve is IMirinCurve {
    uint8 public constant MAX_SWAP_FEE = 100;
    uint8 public constant WEIGHT_SUM = 100;
    uint8 private constant PRECISION = 104;

    function canUpdateData(bytes32, bytes32) external pure override returns (bool) {
        return false;
    }

    function isValidData(bytes32 data) public pure override returns (bool) {
        uint8 weight0 = uint8(uint256(data));
        uint8 weight1 = WEIGHT_SUM - weight0;
        return weight0 > 0 && weight1 > 0;
    }

    function decodeData(bytes32 data, uint8 tokenIn) public pure returns (uint8 weightIn, uint8 weightOut) {
        uint8 weight0 = uint8(uint256(data));
        uint8 weight1 = WEIGHT_SUM - weight0;
        require(weight0 > 0 && weight1 > 0, "MIRIN: INVALID_DATA");
        weightIn = tokenIn == 0 ? weight0 : weight1;
        weightOut = tokenIn == 0 ? weight1 : weight0;
    }

    function computeLiquidity(
        uint256 reserve0,
        uint256 reserve1,
        bytes32 data
    ) external pure override returns (uint256) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        uint256 maxVal = MirinMath.OPT_EXP_MAX_VAL - 1;
        uint256 lnR0 = MirinMath.ln(reserve0 * MirinMath.FIXED_1);
        uint256 lnR1 = MirinMath.ln(reserve1 * MirinMath.FIXED_1);
        uint256 lnLiq = (lnR0 * weight0 + lnR1 * weight1) / (weight0 + weight1);
        uint8 loop = uint8(lnLiq / maxVal);
        uint256 res = lnLiq % maxVal; //lnLiq = maxVal * loop + res

        uint256 liq = MirinMath.optimalExp(res);

        if (loop > 0) {
            uint256 maxValLiq = MirinMath.optimalExp(maxVal);
            uint256 limit = type(uint256).max / maxValLiq;
            for (uint8 i = 0; i < loop; i++) {
                uint256 t = liq / limit;
                liq = liq - (limit * t); //liqIni = limit * t + liqRes
                liq = ((limit * maxValLiq) / MirinMath.FIXED_1) * t + ((liq * maxValLiq) / MirinMath.FIXED_1);
            }
        }
        return liq / MirinMath.FIXED_1;
    }

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external pure override returns (uint224) {
        (uint8 weight0, uint8 weight1) = decodeData(data, 0);
        return
            tokenIn == 0
                ? ((uint224(reserve1) * weight0) << PRECISION) / reserve0 / weight1
                : ((uint224(reserve0) * weight1) << PRECISION) / reserve1 / weight0;
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
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        require(amountIn <= reserveIn / 2, "MIRIN: ERR_MAX_IN_RATIO");

        uint256 weightRatio = MirinMath.roundDiv(uint256(weightIn), uint256(weightOut));
        uint256 adjustedIn = MirinMath.roundMul(amountIn, MirinMath.BASE18 - (uint256(swapFee) * 10**15));
        uint256 base = MirinMath.roundDiv(uint256(reserveIn), uint256(reserveIn) + adjustedIn);
        uint256 pow = MirinMath.power(base, weightRatio);
        amountOut = MirinMath.roundMul(uint256(reserveOut), MirinMath.BASE18 - pow);
    }

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external pure override returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        require(amountOut <= reserveOut / 3, "MIRIN: ERR_MAX_OUT_RATIO");

        uint256 weightRatio = MirinMath.roundDiv(uint256(weightOut), uint256(weightIn));
        uint256 base = MirinMath.roundDiv(uint256(reserveOut), uint256(reserveOut) - amountOut);
        uint256 pow = MirinMath.power(base, weightRatio);
        amountIn = (uint256(reserveIn) * (pow - MirinMath.BASE18)) / (MirinMath.BASE18 - (uint256(swapFee) * 10**15));
    }
}

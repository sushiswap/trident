// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../interfaces/IMirinCurve.sol";
import "../libraries/FixedPoint.sol";
import "../libraries/SafeMath.sol";
import "../libraries/MathUtils.sol";

/**
 * @dev Hybrid curve of constant product and constant sum ones (4a(r_0 +r _1) + k = 4ak + (k^3/4r_0r_1))
 * Excerpted from https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol
 *
 * @author LevX
 */
contract HybridCurve is IMirinCurve {
    using FixedPoint for *;
    using SafeMath for *;
    using MathUtils for uint256;

    // the precision all pools tokens will be converted to
    uint8 private constant POOL_PRECISION_DECIMALS = 18;

    // Constant value used as max loop limit
    uint256 private constant MAX_LOOP_LIMIT = 256;

    // Constant values used in ramping A calculations
    uint256 private constant A_PRECISION = 100;

    modifier onlyValidData(bytes32 data) {
        require(isValidData(data), "MIRIN: INVALID_DATA");
        _;
    }

    function isValidData(bytes32 data) public view override returns (bool) {
        (uint8 decimals0, uint8 decimals1, uint256 A) = decodeData(data);
        return decimals0 <= POOL_PRECISION_DECIMALS && decimals1 <= POOL_PRECISION_DECIMALS && A > 0;
    }

    function computeK(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) public view override onlyValidData(data) returns (uint256) {
        (uint8 decimals0, uint8 decimals1, uint256 A) = decodeData(data);
        uint256[] memory xp = _xp(reserve0, reserve1, decimals0, decimals1);
        return _getD(xp, A);
    }

    function computeLiquidity(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data
    ) external view override onlyValidData(data) returns (uint256) {
        (uint8 decimals0, uint8 decimals1, uint256 A) = decodeData(data);
        uint256[] memory xp = _xp(reserve0, reserve1, decimals0, decimals1);
        return _getD(xp, A);
    }

    function computeLiquidity(uint256 k, bytes32 data) external view override onlyValidData(data) returns (uint256) {
        return k;
    }

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external view override onlyValidData(data) returns (uint256) {
        (uint8 decimals0, uint8 decimals1, uint256 A) = decodeData(data);
        uint256[] memory xp = _xp(reserve0, reserve1, decimals0, decimals1);
        uint256 D = _getD(xp, A);
        return _getYD(A, tokenIn, xp, D);
    }

    function computeAmountOut(
        uint256 amountIn,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view override onlyValidData(data) returns (uint256) {
        (uint8 decimals0, uint8 decimals1, uint256 A) = decodeData(data);
        uint256[] memory xp = _xp(reserve0, reserve1, decimals0, decimals1);
        return _getY(tokenIn == 0 ? 0 : 1, tokenIn == 0 ? 1 : 0, amountIn * (1000 - swapFee), xp, A);
    }

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view override onlyValidData(data) returns (uint256 amountIn) {
        amountIn = 0; // TODO
    }

    function decodeData(bytes32 data)
        public
        pure
        returns (
            uint8 decimals0,
            uint8 decimals1,
            uint256 A
        )
    {
        decimals0 = uint8(uint256(data) >> 248);
        decimals1 = uint8((uint256(data) >> 240) % (1 << 8));
        A = uint240(uint256(data));
    }

    /**
     * @notice Get D, the StableSwap invariant, based on a set of balances and a particular A.
     * See the StableSwap paper for details
     *
     * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L319
     *
     * @param xp a precision-adjusted set of pool balances. Array should be the same cardinality
     * as the pool.
     * @param _A the amplification coefficient * n * (n - 1) in A_PRECISION.
     * See the StableSwap paper for details
     * @return the invariant, at the precision of the pool
     */
    function _getD(uint256[] memory xp, uint256 _A) private pure returns (uint256) {
        uint256 numTokens = xp.length;
        uint256 s;
        for (uint256 i = 0; i < numTokens; i++) {
            s = s.add(xp[i]);
        }
        if (s == 0) {
            return 0;
        }

        uint256 prevD;
        uint256 D = s;
        uint256 nA = _A.mul(numTokens);

        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            uint256 dP = D;
            for (uint256 j = 0; j < numTokens; j++) {
                dP = dP.mul(D).div(xp[j].mul(numTokens));
                // If we were to protect the division loss we would have to keep the denominator separate
                // and divide at the end. However this leads to overflow with large numTokens or/and D.
                // dP = dP * D * D * D * ... overflow!
            }
            prevD = D;
            D = nA.mul(s).div(A_PRECISION).add(dP.mul(numTokens)).mul(D).div(
                nA.div(A_PRECISION).sub(1).mul(D).add(numTokens.add(1).mul(dP))
            );
            if (D.within1(prevD)) {
                break;
            }
        }
        return D;
    }

    /**
     * @notice Calculate the new balances of the tokens given the indexes of the token
     * that is swapped from (FROM) and the token that is swapped to (TO).
     * This function is used as a helper function to calculate how much TO token
     * the user should receive on swap.
     *
     * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L432
     *
     * @param tokenIndexFrom index of FROM token
     * @param tokenIndexTo index of TO token
     * @param x the new total amount of FROM token
     * @param xp balances of the tokens in the pool
     * @return the amount of TO token that should remain in the pool
     */
    function _getY(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 x,
        uint256[] memory xp,
        uint256 _A
    ) private view returns (uint256) {
        uint256 numTokens = xp.length;

        // uint256 _A = _getAPrecise(self);
        uint256 D = _getD(xp, _A);
        //
        // Below is identical to the original code
        //
        uint256 c = D;
        uint256 s;
        uint256 nA = numTokens.mul(_A);

        uint256 _x;
        for (uint256 i = 0; i < numTokens; i++) {
            if (i == tokenIndexFrom) {
                _x = x;
            } else if (i != tokenIndexTo) {
                _x = xp[i];
            } else {
                continue;
            }
            s = s.add(_x);
            c = c.mul(D).div(_x.mul(numTokens));
            // If we were to protect the division loss we would have to keep the denominator separate
            // and divide at the end. However this leads to overflow with large numTokens or/and D.
            // c = c * D * D * D * ... overflow!
        }
        c = c.mul(D).div(nA.mul(numTokens).div(A_PRECISION));
        uint256 b = s.add(D.mul(A_PRECISION).div(nA));
        uint256 yPrev;
        uint256 y = D;

        // iterative approximation
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = y.mul(y).add(c).div(y.mul(2).add(b).sub(D));
            if (y.within1(yPrev)) {
                break;
            }
        }
        return y;
    }

    /**
     * @notice Calculate the price of a token in the pool given
     * precision-adjusted balances and a particular D and precision-adjusted
     * array of balances.
     *
     * @dev This is accomplished via solving the quadratic equation iteratively.
     * See the StableSwap paper and Curve.fi implementation for further details.
     *
     * x_1**2 + x1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
     * x_1**2 + b*x_1 = c
     * x_1 = (x_1**2 + c) / (2*x_1 + b)
     *
     * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L276
     *
     * @param _A the amplification coefficient * n * (n - 1). See the StableSwap paper for details.
     * @param tokenIndex Index of token we are calculating for.
     * @param xp a precision-adjusted set of pool balances. Array should be
     * the same cardinality as the pool.
     * @param D the stableswap invariant
     * @return the price of the token, in the same precision as in xp
     */
    function _getYD(
        uint256 _A,
        uint8 tokenIndex,
        uint256[] memory xp,
        uint256 D
    ) internal pure returns (uint256) {
        uint256 numTokens = xp.length;

        //
        // Below is identical to the original code
        //
        uint256 c = D;
        uint256 s;
        uint256 nA = _A.mul(numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            if (i != tokenIndex) {
                s = s.add(xp[i]);
                c = c.mul(D).div(xp[i].mul(numTokens));
                // If we were to protect the division loss we would have to keep the denominator separate
                // and divide at the end. However this leads to overflow with large numTokens or/and D.
                // c = c * D * D * D * ... overflow!
            } else {
                continue;
            }
        }
        c = c.mul(D).div(nA.mul(numTokens).div(A_PRECISION));

        uint256 b = s.add(D.mul(A_PRECISION).div(nA));
        uint256 yPrev;
        uint256 y = D;
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = y.mul(y).add(c).div(y.mul(2).add(b).sub(D));
            if (y.within1(yPrev)) {
                break;
            }
        }
        return y;
    }

    function _xp(
        uint112 reserve0,
        uint112 reserve1,
        uint8 decimals0,
        uint8 decimals1
    ) private pure returns (uint256[] memory xp) {
        xp = new uint256[](2);
        xp[0] = uint256(reserve0) * 10**(POOL_PRECISION_DECIMALS - decimals0);
        xp[1] = uint256(reserve1) * 10**(POOL_PRECISION_DECIMALS - decimals1);
    }
}

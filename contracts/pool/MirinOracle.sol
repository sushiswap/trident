// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../libraries/MirinMath.sol";
import "../libraries/SafeERC20.sol";

/**
 * @dev Originally DeriswapV1Oracle
 * @author Andre Cronje, LevX
 */
contract MirinOracle {
    using FixedPoint for *;
    using SafeERC20 for IERC20;

    event Sync(uint112 reserve0, uint112 reserve1);

    address public immutable TOKEN0;
    address public immutable TOKEN1;
    uint8 public immutable WEIGHT0;
    uint8 public immutable WEIGHT1;

    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    constructor(
        address _token0,
        address _token1,
        uint8 _weight0,
        uint8 _weight1
    ) {
        TOKEN0 = _token0;
        TOKEN1 = _token1;
        WEIGHT0 = _weight0;
        WEIGHT1 = _weight1;
    }

    struct point {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    point[] public points;

    function pointsLength() external view returns (uint256) {
        return points.length;
    }

    function getWeights() public view returns (uint8 weight0, uint8 weight1) {
        weight0 = WEIGHT0;
        weight1 = WEIGHT1;
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "MIRIN: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast +=
                FixedPoint.encode(_reserve1).mul(WEIGHT0).div(_reserve0).div(WEIGHT1)._x *
                timeElapsed;
            price1CumulativeLast +=
                FixedPoint.encode(_reserve0).mul(WEIGHT1).div(_reserve1).div(WEIGHT0)._x *
                timeElapsed;
            points.push(point(block.timestamp, price0CumulativeLast, price1CumulativeLast));
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(uint112(balance0), uint112(balance1));
    }

    function price(address token) public view returns (uint256) {
        return quotePrice(token, uint256(10)**IERC20(token).decimals());
    }

    function realizedVariance(
        address tokenIn,
        uint256 p,
        uint256 window
    ) external view returns (uint256) {
        return MirinMath.stddev(sample(tokenIn, uint256(10)**IERC20(tokenIn).decimals(), p, window));
    }

    function realizedVolatility(
        address tokenIn,
        uint256 p,
        uint256 window
    ) public view returns (uint256) {
        return MirinMath.vol(sample(tokenIn, uint256(10)**IERC20(tokenIn).decimals(), p, window));
    }

    function computeAmountOut(
        uint256 priceCumulativeStart,
        uint256 priceCumulativeEnd,
        uint256 timeElapsed,
        uint256 amountIn
    ) private pure returns (uint256 amountOut) {
        // overflow is desired.
        FixedPoint.uq112x112 memory priceAverage =
            FixedPoint.uq112x112(uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed));
        amountOut = priceAverage.mul(amountIn).decode144();
    }

    function quotePrice(address tokenIn, uint256 amountIn) public view returns (uint256 amountOut) {
        point memory p = points[points.length - 1];
        if (block.timestamp == p.timestamp) {
            p = points[points.length - 2];
        }

        uint256 timeElapsed = block.timestamp - p.timestamp;
        if (TOKEN0 == tokenIn) {
            return computeAmountOut(p.price0Cumulative, price0CumulativeLast, timeElapsed, amountIn);
        } else {
            return computeAmountOut(p.price1Cumulative, price1CumulativeLast, timeElapsed, amountIn);
        }
    }

    function sample(
        address tokenIn,
        uint256 amountIn,
        uint256 p,
        uint256 window
    ) public view returns (uint256[] memory) {
        uint256[] memory _prices = new uint256[](p);

        uint256 len = points.length - 1;
        uint256 i = len - p * window;
        uint256 nextIndex = 0;
        uint256 index = 0;

        if (TOKEN0 == tokenIn) {
            for (; i < len; i += window) {
                nextIndex = i + window;
                _prices[index] = computeAmountOut(
                    points[i].price0Cumulative,
                    points[nextIndex].price0Cumulative,
                    points[nextIndex].timestamp - points[i].timestamp,
                    amountIn
                );
                index = index + 1;
            }
        } else {
            for (; i < len; i += window) {
                nextIndex = i + window;
                _prices[index] = computeAmountOut(
                    points[i].price1Cumulative,
                    points[nextIndex].price1Cumulative,
                    points[nextIndex].timestamp - points[i].timestamp,
                    amountIn
                );
                index = index + 1;
            }
        }
        return _prices;
    }
}

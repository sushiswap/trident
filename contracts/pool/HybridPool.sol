// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IBentoBox.sol";
import "./MirinERC20.sol";
import "../libraries/MirinMath.sol";
import "../libraries/MathUtils.sol";
import "hardhat/console.sol";
import "../deployer/MasterDeployer.sol";

interface IMirinCallee {
    function mirinCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

contract HybridPool is MirinERC20, IPool {
    using MathUtils for uint256;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;
    uint8 internal constant PRECISION = 112;

    // Constant value used as max loop limit
    uint256 private constant MAX_LOOP_LIMIT = 256;

    uint256 internal constant MAX_FEE = 10000; // 100%
    uint256 public immutable swapFee;

    address public immutable barFeeTo;

    IBentoBoxV1 public immutable bento;
    MasterDeployer public immutable masterDeployer;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint256 public immutable A;
    uint256 internal immutable N_A; // 2 * A
    uint256 internal constant A_PRECISION = 100;

    // multipliers for each pooled token's precision to get to POOL_PRECISION_DECIMALS
    // for example, TBTC has 18 decimals, so the multiplier should be 1. WBTC
    // has 8, so the multiplier should be 10 ** 18 / 10 ** 8 => 10 ** 10
    uint256 public immutable token0PrecisionMultiplier;
    uint256 public immutable token1PrecisionMultiplier;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "MIRIN: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /// @dev
    /// Only set immutable variables here. State changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address tokenA, address tokenB, uint256 _swapFee, uint256 a) = abi.decode(
            _deployData,
            (address, address, uint256, uint256)
        );

        require(tokenA != address(0), "MIRIN: ZERO_ADDRESS");
        require(tokenB != address(0), "MIRIN: ZERO_ADDRESS");
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "MIRIN: INVALID_SWAP_FEE");
        require(a != 0, "MIRIN: ZERO_A");

        (address _token0, address _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        swapFee = _swapFee;
        bento = IBentoBoxV1(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        A = a;
        N_A = 2 * a;
        token0PrecisionMultiplier = uint256(10)**(decimals - MirinERC20(_token0).decimals());
        token1PrecisionMultiplier = uint256(10)**(decimals - MirinERC20(_token1).decimals());
    }

    function init() public {
        require(totalSupply == 0);
        unlocked = 1;
    }

    function mint(address to) public override lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 newLiq = _computeLiquidity(balance0, balance1);
        if (_totalSupply == 0) {
            liquidity = newLiq - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 oldLiq = _computeLiquidity(_reserve0, _reserve1);
            liquidity = ((newLiq - oldLiq) * _totalSupply) / oldLiq;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = newLiq;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(address to) public lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        bento.transfer(token0, address(this), to, amount0);
        bento.transfer(token1, address(this), to, amount1);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function burn(address to, bool unwrapBento) external override returns (liquidityAmount[] memory withdrawnAmounts) {}

    function burnLiquiditySingle(
        address tokenOut,
        address to,
        bool unwrapBento
    ) external override returns (uint256 amount) {}

    function swapWithoutContext(
        address tokenIn,
        address tokenOut,
        address recipient,
        bool unwrapBento
    ) external override returns (uint256 finalAmountOut) {}

    function swapWithContext(
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        bool unwrapBento,
        uint256 amountIn
    ) public override returns (uint256 amountOut) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings

        if (tokenIn == address(token0)) {
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _reserve0, _reserve1, true);
            require(tokenOut == address(token1), "Invalid output token");
            _swap(0, amountOut, recipient, unwrapBento, context, _reserve0, _reserve1, _blockTimestampLast);
        } else if (tokenIn == address(token1)) {
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _reserve1, _reserve0, false);
            require(tokenOut == address(token0), "Invalid output token");
            _swap(amountOut, 0, recipient, unwrapBento, context, _reserve0, _reserve1, _blockTimestampLast);
        } else {
            require(tokenIn == address(this), "Invalid input token");
            require(tokenOut == address(token0) || tokenOut == address(token1), "Invalid output token");
            amountOut = _burnLiquiditySingle(
                amountIn,
                amountOut,
                tokenOut,
                recipient,
                context,
                _reserve0,
                _reserve1,
                _blockTimestampLast
            );
        }
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        _swap(amount0Out, amount1Out, to, false, data, _reserve0, _reserve1, _blockTimestampLast);
    }

    function _getReserves()
        internal
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

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "MIRIN: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        if (blockTimestamp != _blockTimestampLast && _reserve0 != 0 && _reserve1 != 0) {
            unchecked {
                uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
                uint256 xp0 = _reserve0 * token0PrecisionMultiplier;
                uint256 xp1 = _reserve1 * token1PrecisionMultiplier;
                uint256 d = _computeLiquidityFromAdjustedBalances(xp0, xp1);

                uint256 price0 = _getYD(xp0, d);
                price0CumulativeLast += price0 * timeElapsed;
                uint256 price1 = _getYD(xp1, d);
                price1CumulativeLast += price1 * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;

        emit Sync(uint112(balance0), uint112(balance1));
    }

    function _mintFee(
        uint112 _reserve0,
        uint112 _reserve1,
        uint256 _totalSupply
    ) private returns (uint256 computed) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            computed = _computeLiquidity(_reserve0, _reserve1);
            if (computed > _kLast) {
                // barFee % of increase in liquidity
                // NB It's going to be slihgtly less than barFee % in reality due to the Math
                uint256 barFee = MasterDeployer(masterDeployer).barFee();
                uint256 liquidity = (_totalSupply * (computed - _kLast) * barFee) / computed / MAX_FEE;
                if (liquidity > 0) {
                    _mint(barFeeTo, liquidity);
                }
            }
        }
    }

    function _burnLiquiditySingle(
        uint256 amountIn,
        uint256 amountOut,
        address tokenOut,
        address to,
        bytes calldata data,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) internal returns (uint256 finalAmountOut) {
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 amount0;
        uint256 amount1;
        uint256 liquidity;

        if (amountIn > 0) {
            finalAmountOut = _getOutAmountForBurn(tokenOut, amountIn, _totalSupply, _reserve0, _reserve1);

            if (tokenOut == address(token0)) {
                amount0 = finalAmountOut;
            } else {
                amount1 = finalAmountOut;
            }

            _transferWithData(amount0, amount1, to, false, data);

            liquidity = balanceOf[address(this)];
            require(liquidity >= amountIn, "Insufficient liquidity burned");
        } else {
            if (tokenOut == address(token0)) {
                amount0 = amountOut;
            } else {
                amount1 = amountOut;
            }

            _transferWithData(amount0, amount1, to, false, data);
            finalAmountOut = amountOut;

            liquidity = balanceOf[address(this)];
            uint256 allowedAmountOut = _getOutAmountForBurn(tokenOut, liquidity, _totalSupply, _reserve0, _reserve1);
            require(finalAmountOut <= allowedAmountOut, "Insufficient liquidity burned");
        }

        _burn(address(this), liquidity);

        (uint256 balance0, uint256 balance1) = _balance();
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);

        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function _getOutAmountForBurn(
        address tokenOut,
        uint256 liquidity,
        uint256 _totalSupply,
        uint112 _reserve0,
        uint112 _reserve1
    ) internal view returns (uint256 amount) {
        uint256 amount0 = (liquidity * _reserve0) / _totalSupply;
        uint256 amount1 = (liquidity * _reserve1) / _totalSupply;
        if (tokenOut == address(token0)) {
            amount0 += _getAmountOut(amount1, _reserve1 - amount1, _reserve0 - amount0, false);
            return amount0;
        } else {
            amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1, true);
            return amount1;
        }
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = bento.balanceOf(token0, address(this));
        balance1 = bento.balanceOf(token1, address(this));
    }

    function _compute(
        uint256 amount0In,
        uint256 amount1In,
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) internal view {
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        uint256 balance0Adjusted = balance0 * MAX_FEE - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * MAX_FEE - amount1In * swapFee;
        require(
            _computeLiquidity(balance0Adjusted, balance1Adjusted) >=
                _computeLiquidity(uint256(_reserve0) * MAX_FEE, uint256(_reserve1) * MAX_FEE),
            "MIRIN: LIQUIDITY"
        );
    }

    function _transferWithData(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bool unwrapBento,
        bytes calldata data
    ) internal {
        if (amount0Out > 0) {
            if (unwrapBento) {
                IBentoBoxV1(bento).withdraw(token0, address(this), to, amount0Out, 0);
            } else {
                bento.transfer(token0, address(this), to, bento.toShare(token0, amount0Out, false));
            }
        }
        if (amount1Out > 0) {
            if (unwrapBento) {
                IBentoBoxV1(bento).withdraw(token1, address(this), to, amount1Out, 0);
            } else {
                bento.transfer(token1, address(this), to, bento.toShare(token1, amount1Out, false));
            }
        }
        if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0Out, amount1Out, data);
    }

    function _swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bool unwrapBento,
        bytes calldata data,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) internal lock {
        require(amount0Out > 0 || amount1Out > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(to != address(token0) && to != address(token1), "MIRIN: INVALID_TO");
        _transferWithData(amount0Out, amount1Out, to, unwrapBento, data);

        uint256 amount0In;
        uint256 amount1In;
        {
            // scope for _balance{0,1} avoids stack too deep errors
            (uint256 balance0, uint256 balance1) = _balance();
            amount0In = balance0 + amount0Out - _reserve0;
            amount1In = balance1 + amount1Out - _reserve1;
            _compute(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);
            _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        }
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        (uint256 balance0, uint256 balance1) = _balance();
        bento.transfer(token0, address(this), to, bento.toShare(token0, balance0 - reserve0, false));
        bento.transfer(token1, address(this), to, bento.toShare(token1, balance1 - reserve1, false));
    }

    function sync() external lock {
        (uint256 balance0, uint256 balance1) = _balance();
        _update(balance0, balance1, reserve0, reserve1, blockTimestampLast);
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        (uint112 _reserve0, uint112 _reserve1, ) = _getReserves();
        if (IERC20(tokenIn) == token0) {
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1, true);
        } else {
            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0, false);
        }
    }

    function getOptimalLiquidityInAmounts(liquidityInput[] memory liquidityInputs)
        external
        view
        override
        returns (liquidityAmount[] memory)
    {
        uint256 amountA;
        uint256 amountB;
        liquidityAmount[] memory liquidityOptimal = new liquidityAmount[](2);

        if (IERC20(liquidityInputs[0].token) == token0) {
            (amountA, amountB) = _getOptimalLiquidityInAmounts(
                liquidityInputs[0].amountDesired,
                liquidityInputs[0].amountMin,
                liquidityInputs[1].amountDesired,
                liquidityInputs[1].amountMin
            );
        } else {
            (amountB, amountA) = _getOptimalLiquidityInAmounts(
                liquidityInputs[1].amountDesired,
                liquidityInputs[1].amountMin,
                liquidityInputs[0].amountDesired,
                liquidityInputs[0].amountMin
            );
        }
        liquidityOptimal[0] = liquidityAmount({token: liquidityInputs[0].token, amount: amountA});
        liquidityOptimal[1] = liquidityAmount({token: liquidityInputs[1].token, amount: amountB});
        return liquidityOptimal;
    }

    function _getOptimalLiquidityInAmounts(
        uint256 amount0Desired,
        uint256 amount0Min,
        uint256 amount1Desired,
        uint256 amount1Min
    ) internal view returns (uint256 amount0Optimal, uint256 amount1Optimal) {
        (uint256 _reserve0, uint256 _reserve1, ) = _getReserves();

        if (_reserve0 == 0 && _reserve1 == 0) {
            return (amount0Desired, amount1Desired);
        }

        amount1Optimal = (amount0Desired * _reserve1) / _reserve0;
        if (amount1Optimal <= amount1Desired) {
            require(amount1Optimal >= amount1Min, "MIRIN: INSUFFICIENT_B_AMOUNT");
            amount0Optimal = amount0Desired;
        } else {
            amount0Optimal = (amount1Desired * _reserve0) / _reserve1;
            assert(amount0Optimal <= amount0Desired);
            require(amount0Optimal >= amount0Min, "MIRIN: INSUFFICIENT_A_AMOUNT");
            amount1Optimal = amount1Desired;
        }
    }

    /**
     * @notice Get D, the StableSwap invariant, based on a set of balances and a particular A.
     * See the StableSwap paper for details
     *
     * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L319
     *
     * @return the invariant, at the precision of the pool
     */
    function _computeLiquidity(uint256 _reserve0, uint256 _reserve1) internal view returns (uint256) {
        uint256 xp0 = _reserve0 * token0PrecisionMultiplier;
        uint256 xp1 = _reserve1 * token1PrecisionMultiplier;

        return _computeLiquidityFromAdjustedBalances(xp0, xp1);
    }

    function _computeLiquidityFromAdjustedBalances(uint256 xp0, uint256 xp1) internal view returns (uint256) {
        uint256 s = xp0 + xp1;

        if (s == 0) {
            return 0;
        }

        uint256 prevD;
        uint256 D = s;
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            uint256 dP = (((D * D) / xp0) * D) / xp1 / 4;
            prevD = D;
            D = (((N_A * s) / A_PRECISION + 2 * dP) * D) / ((N_A / A_PRECISION - 1) * D + 3 * dP);
            if (D.within1(prevD)) {
                break;
            }
        }
        return D;
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut,
        bool token0In
    ) public view returns (uint256) {
        uint256 tokenInPrecisionMultiplier = (token0In ? token0PrecisionMultiplier : token1PrecisionMultiplier);
        uint256 tokenOutPrecisionMultiplier = (!token0In ? token0PrecisionMultiplier : token1PrecisionMultiplier);

        uint256 xpIn = _reserveIn * tokenInPrecisionMultiplier;
        uint256 xpOut = _reserveOut * tokenOutPrecisionMultiplier;
        amountIn *= tokenInPrecisionMultiplier;

        uint256 d = _computeLiquidityFromAdjustedBalances(xpIn, xpOut);
        uint256 x = xpIn + amountIn;
        uint256 y = _getY(x, d);
        uint256 dy = xpOut - y - 1;
        dy = dy - ((dy * swapFee) / MAX_FEE);
        dy /= tokenOutPrecisionMultiplier;
        return dy;
    }

    /**
     * @notice Calculate the new balances of the tokens given the indexes of the token
     * that is swapped from (FROM) and the token that is swapped to (TO).
     * This function is used as a helper function to calculate how much TO token
     * the user should receive on swap.
     *
     * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L432
     *
     * @param x the new total amount of FROM token
     * @return the amount of TO token that should remain in the pool
     */
    function _getY(uint256 x, uint256 D) private view returns (uint256) {
        uint256 c = (D * D) / (x * 2);
        c = (c * D) / ((N_A * 2) / A_PRECISION);
        uint256 b = x + ((D * A_PRECISION) / N_A);
        uint256 yPrev;
        uint256 y = D;

        // iterative approximation
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = (y * y + c) / (y * 2 + b - D);
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
     * @return the price of the token, in the same precision as in xp
     */
    function _getYD(
        uint256 s, //xpOut
        uint256 d
    ) internal view returns (uint256) {
        uint256 c = (d * d) / (s * 2);
        c = (c * d) / ((N_A * 2) / A_PRECISION);

        uint256 b = s + ((d * A_PRECISION) / N_A);
        uint256 yPrev;
        uint256 y = d;
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = (y * y + c) / (y * 2 + b - d);
            if (y.within1(yPrev)) {
                break;
            }
        }
        return y;
    }
}

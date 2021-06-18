// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../libraries/MirinMathNew.sol";
import "../interfaces/IMirinCurve.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IMirinCallee.sol";

import "./MirinERC20.sol";
import "../interfaces/IBentoBox.sol";
import "hardhat/console.sol";

/**
 * @dev Constant mean curve for tokens with different possible weights (k = r_0^w_0 * r_1^w1)
 * @author LevX
 */
contract ConstantMeanCurve is IMirinCurve {
    uint8 public constant MAX_SWAP_FEE = 100;
    uint8 public constant WEIGHT_SUM = 100;
    uint8 private constant PRECISION = 104;

    function canUpdateData(bytes32, bytes32) public pure override returns (bool) {
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
    ) public pure override returns (uint256) {
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
    ) public pure override returns (uint224) {
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
    ) public pure override returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        require(amountIn <= reserveIn / 2, "MIRIN: ERR_MAX_IN_RATIO");

        uint256 weightRatio = MirinMath.roundDiv(uint256(weightIn), uint256(weightOut));
        uint256 adjustedIn = amountIn * (MirinMath.BASE18 - (uint256(swapFee) * 10**15));
        uint256 base =
            MirinMath.ceilDiv(uint256(reserveIn) * MirinMath.BASE18, uint256(reserveIn) * MirinMath.BASE18 + adjustedIn);
        if (base == MirinMath.BASE18) {
            base = MirinMath.roundDiv(uint256(reserveIn) * MirinMath.BASE18, uint256(reserveIn) * MirinMath.BASE18 + adjustedIn);
        }
        uint256 pow = MirinMath.power(base, weightRatio, false);
        amountOut = (uint256(reserveOut) * (MirinMath.BASE18 - pow)) / MirinMath.BASE18;
    }

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) public pure override returns (uint256 amountIn) {
        require(amountOut > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        (uint112 reserveIn, uint112 reserveOut) = tokenIn == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
        (uint8 weightIn, uint8 weightOut) = decodeData(data, tokenIn);
        require(amountOut <= reserveOut / 3, "MIRIN: ERR_MAX_OUT_RATIO");

        uint256 weightRatio = MirinMath.roundDiv(uint256(weightOut), uint256(weightIn));
        uint256 base = MirinMath.ceilDiv(uint256(reserveOut), uint256(reserveOut) - amountOut);
        uint256 pow = MirinMath.power(base, weightRatio, true);
        uint256 adjustedIn = uint256(reserveIn) * (pow - MirinMath.BASE18);
        uint256 denominator = (MirinMath.BASE18 - (uint256(swapFee) * 10**15));
        amountIn = adjustedIn % denominator == 0 ? adjustedIn / denominator : adjustedIn / denominator + 1;
    }
}

contract MirinPoolBento is ConstantMeanCurve, MirinERC20, IPool {
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

    uint8 public immutable swapFee;
    uint8 public constant MIN_SWAP_FEE = 1;
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;

    address public immutable masterFeeTo;
    address public immutable swapFeeTo;

    IBentoBoxV1 private immutable bento;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    bytes32 public immutable curveData;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "MIRIN: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(bytes memory _deployData) {
        (IBentoBoxV1 _bento, IERC20 tokenA, IERC20 tokenB, bytes32 _curveData, uint8 _swapFee, address _swapFeeTo) =
            abi.decode(_deployData, (IBentoBoxV1, IERC20, IERC20, bytes32, uint8, address));

        (IERC20 _token0, IERC20 _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(address(_token0) != address(0), "MIRIN: ZERO_ADDRESS");
        require(_token0 != _token1, "MIRIN: IDENTICAL_ADDRESSES");
        require(isValidData(_curveData), "MIRIN: INVALID_CURVE_DATA");
        require(_swapFee >= MIN_SWAP_FEE && _swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        bento = _bento;
        token0 = _token0;
        token1 = _token1;
        curveData = _curveData;
        swapFee = _swapFee;
        swapFeeTo = _swapFeeTo;
        masterFeeTo = _swapFeeTo;
    }

    function init() public {
        require(totalSupply == 0);
        unlocked = 1;
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
                uint256 price0 = computePrice(_reserve0, _reserve1, curveData, 0);
                price0CumulativeLast += price0 * timeElapsed;
                uint256 price1 = ConstantMeanCurve.computePrice(_reserve0, _reserve1, curveData, 1);
                price1CumulativeLast += price1 * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;

        emit Sync(uint112(balance0), uint112(balance1));
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (uint256 computed) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            bytes32 _curveData = curveData;
            computed = ConstantMeanCurve.computeLiquidity(_reserve0, _reserve1, _curveData);
            if (computed > _kLast) {
                uint256 numerator = totalSupply * (computed - _kLast);
                uint256 denominator = (computed * (swapFee * 2 - 1)) + _kLast; // 0.05% of increased liquidity
                uint256 liquidity = numerator / denominator;
                if (liquidity > 0) {
                    if (swapFeeTo == address(0)) {
                        _mint(masterFeeTo, liquidity * 2);
                    } else {
                        _mint(masterFeeTo, liquidity);
                        _mint(swapFeeTo, liquidity);
                    }
                }
            }
        }
    }

    function mint(address to) public override lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        bytes32 _curveData = curveData;
        uint256 computed = ConstantMeanCurve.computeLiquidity(uint112(balance0), uint112(balance1), _curveData);
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 k = ConstantMeanCurve.computeLiquidity(uint112(_reserve0), uint112(_reserve1), _curveData);
            liquidity = ((computed - k) * _totalSupply) / k;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(address to) public lock returns (uint256 amount0, uint256 amount1) {
        IERC20 _token0 = IERC20(token0);
        IERC20 _token1 = IERC20(token1);
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        _mintFee(_reserve0, _reserve1);
        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        bento.transfer(_token0, address(this), to, amount0);
        bento.transfer(_token1, address(this), to, amount1);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = ConstantMeanCurve.computeLiquidity(balance0, balance1, curveData);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function burn(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external lock {
        require(amount0 > 0 || amount1 > 0, "MIRIN: INVALID_AMOUNTS");

        uint256 liquidity = balanceOf[address(this)];

        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        _mintFee(_reserve0, _reserve1);

        bytes32 _curveData = curveData;
        uint256 k = ConstantMeanCurve.computeLiquidity(_reserve0, _reserve1, _curveData);
        uint256 computed = ConstantMeanCurve.computeLiquidity(_reserve0 - amount0, _reserve1 - amount1, _curveData);
        uint256 liquidityDelta = ((k - computed) * totalSupply) / k;

        require(liquidityDelta <= liquidity, "MIRIN: LIQUIDITY");
        if (liquidityDelta < liquidity) {
            _transfer(address(this), to, liquidity - liquidityDelta);
            liquidity = liquidityDelta;
        }

        _burn(address(this), liquidity);
        (uint256 balance0, uint256 balance1) = _balance();
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        if (IERC20(tokenIn) == token0) {
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
        } else {
            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
        }
    }

    function getOptimalLiquidityInAmounts(liquidityInput[] memory liquidityInputs)
        external
        view
        override
        returns (liquidityAmount[] memory)
    {
        uint112 _reserve0;
        uint112 _reserve1;
        liquidityAmount[] memory liquidityOptimal = new liquidityAmount[](2);
        liquidityOptimal[0] = liquidityAmount({token: liquidityInputs[0].token, amount: liquidityInputs[0].amountDesired});
        liquidityOptimal[1] = liquidityAmount({token: liquidityInputs[1].token, amount: liquidityInputs[1].amountDesired});

        if (_reserve0 == 0 && _reserve1 == 0) {
            return liquidityOptimal;
        }

        if (IERC20(liquidityInputs[0].token) == token0) {
            (_reserve0, _reserve1, ) = getReserves();
        } else {
            (_reserve1, _reserve0, ) = getReserves();
        }

        uint256 amountBOptimal = (liquidityInputs[0].amountDesired * _reserve1) / _reserve0;
        if (amountBOptimal <= liquidityInputs[1].amountDesired) {
            require(amountBOptimal >= liquidityInputs[1].amountMin, "MIRIN: INSUFFICIENT_B_AMOUNT");
            liquidityOptimal[0].amount = liquidityInputs[0].amountDesired;
            liquidityOptimal[1].amount = amountBOptimal;
        } else {
            uint256 amountAOptimal = (liquidityInputs[1].amountDesired * _reserve1) / _reserve0;
            assert(amountAOptimal <= liquidityInputs[0].amountDesired);
            require(amountAOptimal >= liquidityInputs[0].amountMin, "MIRIN: INSUFFICIENT_A_AMOUNT");
            liquidityOptimal[0].amount = amountAOptimal;
            liquidityOptimal[1].amount = liquidityInputs[1].amountDesired;
        }

        return liquidityOptimal;
    }

    function burnLiquiditySingle(address tokenOut, address to) external returns (uint256 amount) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        _mintFee(_reserve0, _reserve1);
        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 _totalSupply = totalSupply;

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        if (IERC20(tokenOut) == token0) {
            amount0 += _getAmountOut(amount1, _reserve1 - amount1, _reserve0 - amount0);
            bento.transfer(token0, address(this), to, amount0);
            balance0 -= amount0;
            amount = amount0;
        } else {
            amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1);
            bento.transfer(token1, address(this), to, amount1);
            balance1 -= amount1;
            amount = amount1;
        }

        _burn(address(this), liquidity);

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = ConstantMeanCurve.computeLiquidity(balance0, balance1, curveData);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function _balance() private view returns (uint256 balance0, uint256 balance1) {
        (bool success0, bytes memory data0) =
            address(bento).staticcall(abi.encodeWithSelector(bento.balanceOf.selector, token0, address(this)));
        require(success0 && data0.length >= 32);
        balance0 = abi.decode(data0, (uint256));
        (bool success1, bytes memory data1) =
            address(bento).staticcall(abi.encodeWithSelector(bento.balanceOf.selector, token1, address(this)));
        require(success1 && data1.length >= 32);
        balance1 = abi.decode(data1, (uint256));
    }

    function _compute(
        uint256 amount0In,
        uint256 amount1In,
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private view {
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * swapFee;
        require(
            ConstantMeanCurve.computeLiquidity(balance0Adjusted, balance1Adjusted, curveData) >=
                ConstantMeanCurve.computeLiquidity(_reserve0 * 1000, _reserve1 * 1000, curveData) ||
                true,
            "MIRIN: LIQUIDITY"
        );
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) private view returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * (1000 - swapFee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _transferWithData(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data,
        IERC20 _token0,
        IERC20 _token1
    ) private {
        if (amount0Out > 0) bento.transfer(_token0, address(this), to, bento.toShare(_token0, amount0Out, false)); // optimistically transfer tokens
        if (amount1Out > 0) bento.transfer(_token1, address(this), to, bento.toShare(_token1, amount1Out, false)); // optimistically transfer tokens
        if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0Out, amount1Out, data);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        swapInternal(amount0Out, amount1Out, to, data, _reserve0, _reserve1, _blockTimestampLast);
    }

    function swap(
        // formatted for {IPool}
        address tokenIn,
        address,
        bytes calldata context,
        address recipient,
        uint256 amount,
        uint256
    ) external override returns (uint256 oppositeSideAmount) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        //console.log("Reserve0 is %s, Reserve1 is %s", _reserve0, _reserve1);
        if (IERC20(tokenIn) == token0) {
            oppositeSideAmount = _getAmountOut(amount, _reserve0, _reserve1);
            //console.log("Amount out is %s", oppositeSideAmount);
            swapInternal(0, oppositeSideAmount, recipient, context, _reserve0, _reserve1, _blockTimestampLast);
        } else {
            oppositeSideAmount = _getAmountOut(amount, _reserve1, _reserve0);
            //console.log("Amount out is %s", oppositeSideAmount);
            swapInternal(oppositeSideAmount, 0, recipient, context, _reserve0, _reserve1, _blockTimestampLast);
        }
    }

    function swapInternal(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) private lock {
        require(amount0Out > 0 || amount1Out > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(to != address(token0) && to != address(token1), "MIRIN: INVALID_TO");
        _transferWithData(amount0Out, amount1Out, to, data, token0, token1);

        uint256 amount0In;
        uint256 amount1In;
        {
            // scope for _balance{0,1} avoids stack too deep errors
            (uint256 balance0, uint256 balance1) = _balance();
            amount0In = balance0 + amount0Out - _reserve0;
            amount1In = balance1 + amount1Out - _reserve1;
            //console.log("amount0in is %s, amount1In is %s", amount0In, amount1In);
            _compute(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);
            _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        }
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function sync() external lock {
        (uint256 balance0, uint256 balance1) = _balance();
        _update(balance0, balance1, reserve0, reserve1, blockTimestampLast);
    }
}

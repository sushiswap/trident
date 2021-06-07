// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../libraries/MirinMathNew.sol";
import "../interfaces/IMirinCurve.sol";
import "./curves/XYKCurve.sol";
import "./MirinERC20.sol";
import "../interfaces/IBentoBox.sol";
import "../interfaces/IMirinCallee.sol";
import "hardhat/console.sol";

contract MirinPoolBento is XYKCurve, MirinERC20 {
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
    uint8 public constant MAX_SWAP_FEE = 100;
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
        (
            IBentoBoxV1 _bento,
            IERC20 tokenA,
            IERC20 tokenB,
            bytes32 _curveData,
            uint8 _swapFee,
            address _swapFeeTo
        ) = abi.decode(_deployData, (IBentoBoxV1, IERC20, IERC20, bytes32, uint8, address));

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
            bytes32 _curveData = curveData;
            unchecked {
                uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
                price0CumulativeLast += XYKCurve.computePrice(_reserve0, _reserve1, _curveData, 0) * timeElapsed;
                price1CumulativeLast += XYKCurve.computePrice(_reserve0, _reserve1, _curveData, 1) * timeElapsed;
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
            computed = XYKCurve.computeLiquidity(_reserve0, _reserve1, _curveData);
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

    function mint(address to) public lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        (uint256 balance0, uint256 balance1) = _balance(token0, token1);
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        bytes32 _curveData = curveData;
        uint256 computed = XYKCurve.computeLiquidity(uint112(balance0), uint112(balance1), _curveData);
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 k = XYKCurve.computeLiquidity(uint112(_reserve0), uint112(_reserve1), _curveData);
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
        (uint256 balance0, uint256 balance1) = _balance(_token0, _token1);
        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        bento.transfer(_token0, address(this), to, amount0);
        bento.transfer(_token1, address(this), to, amount1);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = XYKCurve.computeLiquidity(balance0, balance1, curveData);
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
        uint256 k = XYKCurve.computeLiquidity(_reserve0, _reserve1, _curveData);
        uint256 computed =
            XYKCurve.computeLiquidity(_reserve0 - amount0, _reserve1 - amount1, _curveData);
        uint256 liquidityDelta = ((k - computed) * totalSupply) / k;

        require(liquidityDelta <= liquidity, "MIRIN: LIQUIDITY");
        if (liquidityDelta < liquidity) {
            _transfer(address(this), to, liquidity - liquidityDelta);
            liquidity = liquidityDelta;
        }

        _burn(address(this), liquidity);
        (uint256 balance0, uint256 balance1) = _balance(token0, token1);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function _balance(IERC20 _token0, IERC20 _token1) private view returns (uint256 balance0, uint256 balance1) {
        (bool success0, bytes memory data0) =
            address(_token0).staticcall(abi.encodeWithSelector(bento.balanceOf.selector, _token0, address(this)));
            require(success0 && data0.length >= 32);
            balance0 = abi.decode(data0, (uint256));
        (bool success1, bytes memory data1) =
            address(_token1).staticcall(abi.encodeWithSelector(bento.balanceOf.selector, _token1, address(this)));
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
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * swapFee;
        bytes32 _curveData = curveData;
        require(
            XYKCurve.computeLiquidity(balance0Adjusted, balance1Adjusted, _curveData) >=
            XYKCurve.computeLiquidity(_reserve0 * 1000, _reserve1 * 1000, _curveData),
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

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) public lock {
        require(amount0Out > 0 || amount1Out > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "MIRIN: INSUFFICIENT_LIQUIDITY");
        uint256 balance0;
        uint256 balance1;
        { // scope avoids stack too deep errors
        IERC20 _token0 = token0; // gas savings
        IERC20 _token1 = token1; // gas savings
        require(to != address(_token0) && to != address(_token1), "MIRIN: INVALID_TO");
        _transferWithData(amount0Out, amount1Out, to, data, _token0, _token1);
        (balance0, balance1) = _balance(_token0, _token1);
        }
        { // scope avoids stack too deep errors
        uint256 amount0In = balance0 + amount0Out - _reserve0;
        uint256 amount1In = balance1 + amount1Out - _reserve1;
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        console.log("amount0in is %s, amount1In is %s", amount0In, amount1In);
        _compute(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        // emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        }
    }

    function swap( // formatted for {IPool}
        address tokenIn,
        address,
        bytes calldata context,
        address recipient,
        bool,
        uint256 amount
    ) external returns (uint256 oppositeSideAmount) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        console.log("Reserve0 is %s, Reserve1 is %s", _reserve0, _reserve1);
        if (IERC20(tokenIn) == token0) {
            oppositeSideAmount = _getAmountOut(amount, _reserve0, _reserve1);
            console.log("Amount out is %s", oppositeSideAmount);
            swap(0, oppositeSideAmount, recipient, context);
        } else {
            oppositeSideAmount = _getAmountOut(amount, _reserve1, _reserve0);
            console.log("Amount out is %s", oppositeSideAmount);
            swap(oppositeSideAmount, 0, recipient, context);
        }
    }

    function sync() external lock {
        (uint256 balance0, uint256 balance1) = _balance(token0, token1);
        _update(
            balance0,
            balance1,
            reserve0,
            reserve1,
            blockTimestampLast
        );
    }
}

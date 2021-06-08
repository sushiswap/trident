// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../interfaces/IPool.sol";
import "../interfaces/IBentoBox.sol";
import "./MirinERC20.sol";
import "../libraries/MirinMath.sol";
import "hardhat/console.sol";

interface IMirinCallee {
    function mirinCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

contract ConstantProductPool is MirinERC20, IPool {
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
    uint8 internal constant MAX_SWAP_FEE = 100;
    uint8 internal constant MIN_SWAP_FEE = 1;
    uint8 public immutable swapFee;

    address public immutable masterFeeTo;
    address public immutable swapFeeTo;

    IBentoBoxV1 private immutable bento;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

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

    modifier ensureDeadline(uint256 deadline) {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        _;
    }

    /// @dev
    /// Only set immutable variables here. State changes made here will not be used.
    constructor(bytes memory _deployData) {
        (IBentoBoxV1 _bento, IERC20 tokenA, IERC20 tokenB, uint8 _swapFee, address _swapFeeTo) =
            abi.decode(_deployData, (IBentoBoxV1, IERC20, IERC20, uint8, address));

        (IERC20 _token0, IERC20 _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(address(_token0) != address(0), "MIRIN: ZERO_ADDRESS");
        require(_token0 != _token1, "MIRIN: IDENTICAL_ADDRESSES");
        require(_swapFee >= MIN_SWAP_FEE && _swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        bento = _bento;
        token0 = _token0;
        token1 = _token1;
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
                uint256 price0 = (uint256(_reserve1) << PRECISION) / _reserve0;
                price0CumulativeLast += price0 * timeElapsed;
                uint256 price1 = (uint256(_reserve0) << PRECISION) / _reserve1;
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
            computed = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
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
        uint256 balance0 = bento.balanceOf(token0, address(this));
        uint256 balance1 = bento.balanceOf(token1, address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        uint256 computed = MirinMath.sqrt(balance0 * balance1);
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 k = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
            liquidity = ((computed - k) * _totalSupply) / k;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(address to) public lock returns (uint256 amount0, uint256 amount1) {
        IERC20 _token0 = IERC20(token0); // gas savings
        IERC20 _token1 = IERC20(token1); // gas savings
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
        kLast = MirinMath.sqrt(balance0 * balance1);
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

        uint256 k = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
        uint256 computed = MirinMath.sqrt(uint256(_reserve0) - amount0 * _reserve1 - amount1);
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

    function getAmountOut(address tokenIn, uint256 amountIn) public view returns (uint256 amountOut) {
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

        if (IERC20(liquidityInputs[0].token) == token0) {
            (_reserve0, _reserve1, ) = getReserves();
        } else {
            (_reserve1, _reserve0, ) = getReserves();
        }

        if (_reserve0 == 0 && _reserve1 == 0) {
            return liquidityOptimal;
        }

        uint256 amountBOptimal = (liquidityInputs[0].amountDesired * _reserve1) / _reserve0;
        if (amountBOptimal <= liquidityInputs[1].amountDesired) {
            require(amountBOptimal >= liquidityInputs[1].amountMin, "MIRIN: INSUFFICIENT_B_AMOUNT");
            liquidityOptimal[0].amount = liquidityInputs[0].amountDesired;
            liquidityOptimal[1].amount = amountBOptimal;
        } else {
            uint256 amountAOptimal = (liquidityInputs[1].amountDesired * _reserve0) / _reserve1;
            assert(amountAOptimal <= liquidityInputs[0].amountDesired);
            require(amountAOptimal >= liquidityInputs[0].amountMin, "MIRIN: INSUFFICIENT_A_AMOUNT");
            liquidityOptimal[0].amount = amountAOptimal;
            liquidityOptimal[1].amount = liquidityInputs[1].amountDesired;
        }

        return liquidityOptimal;
    }

    function burnLiquiditySingle(address tokenOut, address to) external override returns (uint256 amount) {
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
        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function _balance() private view returns (uint256 balance0, uint256 balance1) {
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
    ) private view {
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * swapFee;
        require(
            MirinMath.sqrt(balance0Adjusted * balance1Adjusted) >= MirinMath.sqrt(uint256(_reserve0) * _reserve1 * 1000000),
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
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves(); // gas savings
        swapInternal(amount0Out, amount1Out, to, data, _reserve0, _reserve1, _blockTimestampLast);
    }

    function swap(
        // formatted for {IPool}
        address tokenIn,
        address,
        bytes calldata context,
        address recipient,
        uint256 amount
    ) external override returns (uint256 oppositeSideAmount) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves(); // gas savings
        if (IERC20(tokenIn) == token0) {
            oppositeSideAmount = _getAmountOut(amount, _reserve0, _reserve1);
            swapInternal(0, oppositeSideAmount, recipient, context, _reserve0, _reserve1, _blockTimestampLast);
        } else {
            oppositeSideAmount = _getAmountOut(amount, _reserve1, _reserve0);
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
    ) internal lock {
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
            _compute(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);
            _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        }
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function sync() external lock {
        _update(
            bento.balanceOf(token0, address(this)),
            bento.balanceOf(token1, address(this)),
            reserve0,
            reserve1,
            blockTimestampLast
        );
    }
}

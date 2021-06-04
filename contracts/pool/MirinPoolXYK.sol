// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./MirinERC20.sol";
import "../interfaces/IBentoBox.sol";
import "hardhat/console.sol";

interface IMirinCallee {
    function mirinCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract MirinPoolBento is MirinERC20 {
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

    modifier ensureDeadline(uint256 deadline) {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        _;
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

    /// @notice Update reserves and, on the first call per block, price accumulators.
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'Boshi: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(BoshiMath.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(BoshiMath.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    /// @notice If fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k).
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address _feeTo = masterContract.feeTo();
        feeOn = _feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = BoshiMath.sqrt(uint256(_reserve0).mul(_reserve1));
                uint256 rootKLast = BoshiMath.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint256 denominator = rootK.mul(5).add(rootKLast);
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    /// @notice This low-level function should be called from a contract which performs important safety checks.
    function mint(address to) private returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        uint256 balance0 = bentoBox.balanceOf(token0, address(this));
        uint256 balance1 = bentoBox.balanceOf(token1, address(this));
        uint256 amount0 = balance0.sub(_reserve0);
        uint256 amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            IMigrator _migrator = IMigrator(masterContract.migrator());
            if (msg.sender == address(_migrator)) {
                liquidity = _migrator.desiredLiquidity();
                require(liquidity > 0 && liquidity != type(uint256).max, 'Boshi: BAD_DESIRED_LIQUIDITY');
            } else {
                require(address(_migrator) == address(0), 'Boshi: MUST_NOT_HAVE_MIGRATOR');
                liquidity = BoshiMath.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
                _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
            }
        } else {
            liquidity = BoshiMath.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'Boshi: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    /// @notice This low-level function should be called from a contract which performs important safety checks.
    function burn(address to) private returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        IERC20 _token0 = token0;                                 // gas savings
        IERC20 _token1 = token1;                                 // gas savings
        uint256 balance0 = bentoBox.balanceOf(_token0, address(this));
        uint256 balance1 = bentoBox.balanceOf(_token1, address(this));
        uint256 liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'Boshi: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        bentoBox.transfer(_token0, address(this), to, amount0);
        bentoBox.transfer(_token1, address(this), to, amount1);
        balance0 = bentoBox.balanceOf(_token0, address(this));
        balance1 = bentoBox.balanceOf(_token1, address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
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

    /// @notice This low-level function should be called from a contract which performs important safety checks.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'Boshi: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Boshi: INSUFFICIENT_LIQUIDITY');
        
        uint256 balance0;
        uint256 balance1;
        { // scope for _token{0,1} avoids stack too deep errors
        IERC20 _token0 = token0;
        IERC20 _token1 = token1;
        require(to != address(_token0) && to != address(_token1), 'Boshi: INVALID_TO');
        if (amount0Out > 0) bentoBox.transfer(_token0, address(this), to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) bentoBox.transfer(_token1, address(this), to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IBoshiCallee(to).boshiCall(msg.sender, amount0Out, amount1Out, data);
        balance0 = bentoBox.balanceOf(_token0, address(this));
        balance1 = bentoBox.balanceOf(_token1, address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'Boshi: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1} Adjusted, avoids stack too deep errors
        uint256 balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
        uint256 balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint256(_reserve0).mul(_reserve1).mul(1000**2), 'Boshi: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function swap( // formatted for {IPool}
        address tokenIn,
        address,
        bytes calldata context,
        address recipient,
        bool,
        uint256 amount
    ) external returns (uint256 oppositeSideAmount) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
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
        _update(
            bento.balanceOf(token0, address(this)),
            bento.balanceOf(token1, address(this)),
            reserve0,
            reserve1,
            blockTimestampLast
        );
    }
}

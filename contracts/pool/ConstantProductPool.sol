// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "../interfaces/IPool.sol";
import "../interfaces/IBentoBox.sol";
import "../interfaces/IMirinCallee.sol";
import "./MirinERC20.sol";
import "../libraries/MirinMath.sol";
import "hardhat/console.sol";
import "../deployer/MasterDeployer.sol";

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

    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;

    uint8 internal constant PRECISION = 112;
    uint256 internal constant MAX_FEE = 10000; // 100%
    uint256 internal constant MAX_FEE_SQUARE = 100000000;
    uint256 public immutable swapFee;
    uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE;

    address public immutable barFeeTo;

    IBentoBoxV1 private immutable bento;
    MasterDeployer public immutable masterDeployer;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public kLast;

    uint128 internal reserve0;
    uint128 internal reserve1;

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
        (IERC20 tokenA, IERC20 tokenB, uint256 _swapFee) = abi.decode(_deployData, (IERC20, IERC20, uint256));

        require(address(tokenA) != address(0), "MIRIN: ZERO_ADDRESS");
        require(address(tokenB) != address(0), "MIRIN: ZERO_ADDRESS");
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "MIRIN: INVALID_SWAP_FEE");

        (IERC20 _token0, IERC20 _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxV1(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
    }

    function mint(address to) public override lock returns (uint256 liquidity) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

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
        _update(balance0, balance1);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(address to, bool unwrapBento) public lock returns (uint256 amount0, uint256 amount1) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        _transferWithoutData(amount0, amount1, to, unwrapBento);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1);
        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function burnLiquiditySingle(
        address tokenOut,
        address to,
        bool unwrapBento
    ) public lock returns (uint256 amount0, uint256 amount1) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        if (tokenOut == address(token0)) {
            // Swap token1 for token0
            // Calculate amountOut as if the user first withdrew balanced liquidity and then swapped token1 for token0
            amount0 += _getAmountOut(amount1, _reserve0 - amount0, _reserve1 - amount1);
            _transfer(token0, amount0, to, unwrapBento);
            balance0 -= amount0;
        } else {
            // Swap token0 for token1
            require(tokenOut == address(token1), "Invalid output token");
            amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1);
            _transfer(token1, amount1, to, unwrapBento);
            balance1 -= amount1;
        }

        _update(balance0, balance1);
        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swapWithoutContext(
        address tokenIn,
        address tokenOut,
        address recipient,
        bool unwrapBento
    ) external override lock returns (uint256 amountOut) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        (uint256 balance0, uint256 balance1) = _balance();

        if (tokenIn == address(token0)) {
            require(tokenOut == address(token1), "Invalid output token");
            uint256 amountIn = balance0 - _reserve0;
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            _transfer(token1, amountOut, recipient, unwrapBento);
            _update(balance0, balance1 - amountOut);
            emit Swap(msg.sender, amountIn, 0, 0, amountOut, recipient);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");
            uint256 amountIn = balance1 - _reserve1;
            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            _transfer(token0, amountOut, recipient, unwrapBento);
            _update(balance0 - amountOut, balance1);
            emit Swap(msg.sender, 0, amountIn, amountOut, 0, recipient);
        }
    }

    function swapWithContext(
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        bool unwrapBento,
        uint256 amountIn
    ) public override lock returns (uint256 amountOut) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);

        if (tokenIn == address(token0)) {
            require(tokenOut == address(token1), "Invalid output token");
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            _swapWithData(0, amountOut, recipient, unwrapBento, context, _reserve0, _reserve1);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            _swapWithData(amountOut, 0, recipient, unwrapBento, context, _reserve0, _reserve1);
        }
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external lock {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        _swapWithData(amount0Out, amount1Out, to, false, data, _reserve0, _reserve1);
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        require(balance0 < type(uint128).max && balance1 < type(uint128).max, "MIRIN: OVERFLOW");
        reserve0 = uint128(balance0);
        reserve1 = uint128(balance1);
    }

    function _mintFee(
        uint128 _reserve0,
        uint128 _reserve1,
        uint256 _totalSupply
    ) internal returns (uint256 computed) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            computed = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
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

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = bento.balanceOf(token0, address(this));
        balance1 = bento.balanceOf(token1, address(this));
    }

    function _compute(
        uint256 amount0In,
        uint256 amount1In,
        uint256 balance0,
        uint256 balance1,
        uint128 _reserve0,
        uint128 _reserve1
    ) internal view {
        uint256 balance0Adjusted = balance0 * MAX_FEE - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * MAX_FEE - amount1In * swapFee;
        require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * MAX_FEE_SQUARE, "MIRIN: LIQUIDITY");
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * MAX_FEE_MINUS_SWAP_FEE;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * MAX_FEE + amountInWithFee);
    }

    function _transfer(
        IERC20 token,
        uint256 amount,
        address to,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            IBentoBoxV1(bento).withdraw(token, address(this), to, amount, 0);
        } else {
            bento.transfer(token, address(this), to, bento.toShare(token, amount, false));
        }
    }

    function _transferWithoutData(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bool unwrapBento
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
    }

    function _swapWithData(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bool unwrapBento,
        bytes calldata data,
        uint128 _reserve0,
        uint128 _reserve1
    ) internal {
        _transferWithoutData(amount0Out, amount1Out, to, unwrapBento);
        if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0Out, amount1Out, data);
        _swap(amount0Out, amount1Out, to, _reserve0, _reserve1);
    }

    function _swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        uint128 _reserve0,
        uint128 _reserve1
    ) internal {
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0In = balance0 + amount0Out - _reserve0;
        uint256 amount1In = balance1 + amount1Out - _reserve1;
        _compute(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);
        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function getAmountOut(
        address tokenIn,
        address, /*tokenOut*/
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
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
        if (IERC20(liquidityInputs[0].token) == token1) {
            // Swap tokens to be in order
            (liquidityInputs[0], liquidityInputs[1]) = (liquidityInputs[1], liquidityInputs[0]);
        }
        uint128 _reserve0;
        uint128 _reserve1;
        liquidityAmount[] memory liquidityOptimal = new liquidityAmount[](2);
        liquidityOptimal[0] = liquidityAmount({token: liquidityInputs[0].token, amount: liquidityInputs[0].amountDesired});
        liquidityOptimal[1] = liquidityAmount({token: liquidityInputs[1].token, amount: liquidityInputs[1].amountDesired});

        (_reserve0, _reserve1) = (reserve0, reserve1);

        if (_reserve0 == 0) {
            return liquidityOptimal;
        }

        uint256 amount1Optimal = (liquidityInputs[0].amountDesired * _reserve1) / _reserve0;
        if (amount1Optimal <= liquidityInputs[1].amountDesired) {
            require(amount1Optimal >= liquidityInputs[1].amountMin, "INSUFFICIENT_B_AMOUNT");
            liquidityOptimal[1].amount = amount1Optimal;
        } else {
            uint256 amount0Optimal = (liquidityInputs[1].amountDesired * _reserve0) / _reserve1;
            require(amount0Optimal >= liquidityInputs[0].amountMin, "INSUFFICIENT_A_AMOUNT");
            liquidityOptimal[0].amount = amount0Optimal;
        }

        return liquidityOptimal;
    }
}

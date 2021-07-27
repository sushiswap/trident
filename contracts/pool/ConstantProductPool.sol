// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../deployer/MasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "./TridentERC20.sol";
import "hardhat/console.sol";

/// @notice Trident pool template with constant product formula for swapping between an ERC-20 token pair.
/// @dev This pool swaps between bento shares - it does not care about underlying amounts.
contract ConstantProductPool is IPool, TridentERC20 {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Sync(uint256 reserve0, uint256 reserve1);

    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    uint256 internal constant MAX_FEE = 10000; // @dev 100%.
    uint256 internal constant MAX_FEE_SQUARE = 100000000;
    uint256 public immutable swapFee;
    uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE;

    address internal immutable barFeeTo;
    IBentoBoxMinimal internal immutable bento;
    MasterDeployer internal immutable masterDeployer;

    address public immutable token0;
    address public immutable token1;

    uint256 public kLast;

    uint128 internal reserve0;
    uint128 internal reserve1;

    uint256 public constant override poolType = 1;
    uint256 public constant override assetsCount = 2;
    address[] public override assets;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "ConstantProductPool: LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address tokenA, address tokenB, uint256 _swapFee) = abi.decode(_deployData, (address, address, uint256));

        require(tokenA != address(0), "ConstantProductPool: ZERO_ADDRESS");
        require(tokenB != address(0), "ConstantProductPool: ZERO_ADDRESS");
        require(tokenA != tokenB, "ConstantProductPool: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "ConstantProductPool: INVALID_SWAP_FEE");

        token0 = tokenA;
        token1 = tokenB;
        assets.push(tokenA);
        assets.push(tokenB);
        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxMinimal(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
    }

    /// @notice Adapted from https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol.
    /// Copyright © 2019 by ABDK Consulting, License-Identifier: BSD-4-Clause.
    /// @dev Calculate sqrt (x) rounding down, where x is unsigned 256-bit integer number.
    /// @param x Unsigned 256-bit integer number.
    /// @return calculated Unsigned 256-bit integer number.
    function sqrt(uint256 x) internal pure returns (uint256 calculated) {
        unchecked {
            if (x == 0) calculated = 0;
            else {
                uint256 xx = x;
                uint256 r = 1;
                if (xx >= 0x100000000000000000000000000000000) {
                    xx >>= 128;
                    r <<= 64;
                }
                if (xx >= 0x10000000000000000) {
                    xx >>= 64;
                    r <<= 32;
                }
                if (xx >= 0x100000000) {
                    xx >>= 32;
                    r <<= 16;
                }
                if (xx >= 0x10000) {
                    xx >>= 16;
                    r <<= 8;
                }
                if (xx >= 0x100) {
                    xx >>= 8;
                    r <<= 4;
                }
                if (xx >= 0x10) {
                    xx >>= 4;
                    r <<= 2;
                }
                if (xx >= 0x8) {
                    r <<= 1;
                }
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1; // @dev Seven iterations should be enough.
                uint256 r1 = x / r;
                r < r1 ? calculated = r : r1;
            }
        }
    }

    function mint(address recipient) public override lock returns (uint256 liquidity) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 computed = sqrt(balance0 * balance1);
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 k = sqrt(uint256(_reserve0) * _reserve1);
            liquidity = ((computed - k) * _totalSupply) / k;
        }
        require(liquidity > 0, "ConstantProductPool: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(recipient, liquidity);
        _update(balance0, balance1);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, recipient);
    }

    function burn(address recipient, bool unwrapBento)
        public
        override
        lock
        returns (liquidityAmount[] memory withdrawnAmounts)
    {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        address _token0 = token0;
        address _token1 = token1;

        _transfer(_token0, amount0, recipient, unwrapBento);
        _transfer(_token1, amount1, recipient, unwrapBento);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1);
        kLast = sqrt(balance0 * balance1);

        withdrawnAmounts = new liquidityAmount[](2);
        withdrawnAmounts[0] = liquidityAmount({token: _token0, amount: amount0});
        withdrawnAmounts[1] = liquidityAmount({token: _token1, amount: amount1});

        emit Burn(msg.sender, amount0, amount1, recipient);
    }

    function burnLiquiditySingle(
        address tokenOut,
        address recipient,
        bool unwrapBento
    ) public override lock returns (uint256 amount) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        if (tokenOut == token0) {
            // @dev Swap token1 for token0.
            // @dev Calculate amountOut as if the user first withdrew balanced liquidity and then swapped token1 for token0.
            amount0 += _getAmountOut(amount1, _reserve1 - amount1, _reserve0 - amount0);
            _transfer(token0, amount0, recipient, unwrapBento);
            balance0 -= amount0;
            amount = amount0;
        } else {
            // @dev Swap token0 for token1.
            require(tokenOut == token1, "ConstantProductPool: INVALID_OUTPUT_TOKEN");
            amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1);
            _transfer(token1, amount1, recipient, unwrapBento);
            balance1 -= amount1;
            amount = amount1;
        }
        _update(balance0, balance1);
        kLast = sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, recipient);
    }

    function swapWithoutContext(
        address tokenIn,
        address tokenOut,
        address recipient,
        bool unwrapBento
    ) external override lock returns (uint256 amountOut) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amountIn;

        if (tokenIn == token0) {
            require(tokenOut == token1, "ConstantProductPool: INVALID_OUTPUT_TOKEN");
            amountIn = balance0 - _reserve0;
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            _transfer(token1, amountOut, recipient, unwrapBento);
            _update(balance0, balance1 - amountOut);
        } else {
            require(tokenIn == token1, "ConstantProductPool: INVALID_INPUT_TOKEN");
            require(tokenOut == token0, "ConstantProductPool: INVALID_OUTPUT_TOKEN");
            amountIn = balance1 - _reserve1;
            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            _transfer(token0, amountOut, recipient, unwrapBento);
            _update(balance0 - amountOut, balance1);
        }
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
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

        if (tokenIn == token0) {
            require(tokenOut == token1, "ConstantProductPool: INVALID_OUTPUT_TOKEN");

            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            _processSwap(tokenIn, tokenOut, recipient, amountIn, amountOut, context, unwrapBento);

            (uint256 balance0, uint256 balance1) = _balance();
            require(balance0 - _reserve0 >= amountIn, "ConstantProductPool: INSUFFICIENT_AMOUNT_IN");

            _update(balance0, balance1 - amountOut);
        } else {
            require(tokenIn == token1, "ConstantProductPool: INVALID_INPUT_TOKEN");
            require(tokenOut == token0, "ConstantProductPool: INVALID_OUTPUT_TOKEN");

            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            _processSwap(tokenIn, tokenOut, recipient, amountIn, amountOut, context, unwrapBento);

            (uint256 balance0, uint256 balance1) = _balance();
            require(balance1 - _reserve1 >= amountIn, "ConstantProductPool: INSUFFICIENT_AMOUNT_IN");

            _update(balance0 - amountOut, balance1);
        }
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function _processSwap(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata data,
        bool unwrapBento
    ) internal {
        _transfer(tokenOut, amountOut, recipient, unwrapBento);
        if (data.length != 0) ITridentCallee(recipient).tridentCallback(tokenIn, tokenOut, amountIn, amountOut, data);
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        require(balance0 < type(uint128).max && balance1 < type(uint128).max, "ConstantProductPool: OVERFLOW");
        reserve0 = uint128(balance0);
        reserve1 = uint128(balance1);
        emit Sync(balance0, balance1);
    }

    function _mintFee(
        uint128 _reserve0,
        uint128 _reserve1,
        uint256 _totalSupply
    ) internal returns (uint256 computed) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            computed = sqrt(uint256(_reserve0) * _reserve1);
            if (computed > _kLast) {
                // @dev barFee % of increase in liquidity.
                // NB It's going to be slightly less than barFee % in reality due to the Math.
                uint256 barFee = MasterDeployer(masterDeployer).barFee();
                uint256 liquidity = (_totalSupply * (computed - _kLast) * barFee) / computed / MAX_FEE;
                if (liquidity != 0) {
                    _mint(barFeeTo, liquidity);
                }
            }
        }
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = bento.balanceOf(token0, address(this));
        balance1 = bento.balanceOf(token1, address(this));
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
        address token,
        uint256 amount,
        address to,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token, address(this), to, 0, amount);
        } else {
            bento.transfer(token, address(this), to, amount);
        }
    }

    function getAmountOut(
        address tokenIn,
        address, // @dev `tokenOut`.
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        if (tokenIn == token0) {
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
        if (liquidityInputs[0].token == token1) {
            // @dev Swap tokens to be in order.
            (liquidityInputs[0], liquidityInputs[1]) = (liquidityInputs[1], liquidityInputs[0]);
        }
        liquidityAmount[] memory liquidityOptimal = new liquidityAmount[](2);
        liquidityOptimal[0] = liquidityAmount({
            token: liquidityInputs[0].token,
            amount: liquidityInputs[0].amountDesired
        });
        liquidityOptimal[1] = liquidityAmount({
            token: liquidityInputs[1].token,
            amount: liquidityInputs[1].amountDesired
        });

        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);

        if (_reserve0 == 0) {
            return liquidityOptimal;
        }
        uint256 amount1Optimal = (liquidityInputs[0].amountDesired * _reserve1) / _reserve0;
        if (amount1Optimal <= liquidityInputs[1].amountDesired) {
            require(amount1Optimal >= liquidityInputs[1].amountMin, "ConstantProductPool: INSUFFICIENT_B_AMOUNT");
            liquidityOptimal[1].amount = amount1Optimal;
        } else {
            uint256 amount0Optimal = (liquidityInputs[1].amountDesired * _reserve0) / _reserve1;
            require(amount0Optimal >= liquidityInputs[0].amountMin, "ConstantProductPool: INSUFFICIENT_A_AMOUNT");
            liquidityOptimal[0].amount = amount0Optimal;
        }
        return liquidityOptimal;
    }
}

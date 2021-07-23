// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "../interfaces/IPool.sol";
import "../interfaces/IBentoBox.sol";
import "../interfaces/ITridentCallee.sol";
import "./MirinERC20.sol";
import "../libraries/MirinMath.sol";
import "hardhat/console.sol";
import "../deployer/MasterDeployer.sol";

/// @dev This pool swaps between bento shares. It does not care about underlying amounts.
contract ConstantProductPool is MirinERC20, IPool {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event sync(uint256 reserve0, uint256 reserve1);

    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    uint256 internal constant MAX_FEE = 10000; // 100%
    uint256 internal constant MAX_FEE_SQUARE = 100000000;
    uint256 public immutable swapFee;
    uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE;

    address internal immutable barFeeTo;
    IBentoBoxV1 internal immutable bento;
    MasterDeployer internal immutable masterDeployer;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public kLast;

    uint128 internal reserve0;
    uint128 internal reserve1;

    uint256 public constant override poolType = 1;
    uint256 public constant override assetsCount = 2;
    address[] public override assets;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "MIRIN: LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    /// @dev
    /// Only set immutable variables here. State changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) MirinERC20() {
        (IERC20 tokenA, IERC20 tokenB, uint256 _swapFee) = abi.decode(_deployData, (IERC20, IERC20, uint256));

        require(address(tokenA) != address(0), "MIRIN: ZERO_ADDRESS");
        require(address(tokenB) != address(0), "MIRIN: ZERO_ADDRESS");
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "MIRIN: INVALID_SWAP_FEE");

        token0 = tokenA;
        token1 = tokenB;
        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxV1(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
        assets.push(address(tokenA));
        assets.push(address(tokenB));
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

    function burn(address to, bool unwrapBento)
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

        _transfer(token0, amount0, to, unwrapBento);
        _transfer(token1, amount1, to, unwrapBento);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1);
        kLast = MirinMath.sqrt(balance0 * balance1);

        withdrawnAmounts = new liquidityAmount[](2);
        withdrawnAmounts[0] = liquidityAmount({token: address(token0), amount: amount0});
        withdrawnAmounts[1] = liquidityAmount({token: address(token1), amount: amount1});

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function burnLiquiditySingle(
        address tokenOut,
        address to,
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

        if (tokenOut == address(token0)) {
            // Swap token1 for token0
            // Calculate amountOut as if the user first withdrew balanced liquidity and then swapped token1 for token0
            amount0 += _getAmountOut(amount1, _reserve1 - amount1, _reserve0 - amount0);
            _transfer(token0, amount0, to, unwrapBento);
            balance0 -= amount0;
            amount = amount0;
        } else {
            // Swap token0 for token1
            require(tokenOut == address(token1), "Invalid output token");
            amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1);
            _transfer(token1, amount1, to, unwrapBento);
            balance1 -= amount1;
            amount = amount1;
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
        uint256 amountIn;

        if (tokenIn == address(token0)) {
            require(tokenOut == address(token1), "Invalid output token");
            amountIn = balance0 - _reserve0;
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            _transfer(token1, amountOut, recipient, unwrapBento);
            _update(balance0, balance1 - amountOut);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");
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

        if (tokenIn == address(token0)) {
            require(tokenOut == address(token1), "Invalid output token");

            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            _processSwap(tokenIn, tokenOut, recipient, amountIn, amountOut, context, unwrapBento);

            (uint256 balance0, uint256 balance1) = _balance();
            require(balance0 - _reserve0 >= amountIn, "Insuffficient amount in");

            _update(balance0, balance1 - amountOut);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");

            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            _processSwap(tokenIn, tokenOut, recipient, amountIn, amountOut, context, unwrapBento);

            (uint256 balance0, uint256 balance1) = _balance();
            require(balance1 - _reserve1 >= amountIn, "Insuffficient amount in");

            _update(balance0 - amountOut, balance1);
        }

        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function _processSwap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata data,
        bool unwrapBento
    ) internal {
        _transfer(IERC20(tokenOut), amountOut, to, unwrapBento);
        if (data.length > 0) ITridentCallee(to).tridentCallback(tokenIn, tokenOut, amountIn, amountOut, data);
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        require(balance0 < type(uint128).max && balance1 < type(uint128).max, "MIRIN: OVERFLOW");
        reserve0 = uint128(balance0);
        reserve1 = uint128(balance1);
        emit sync(balance0, balance1);
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
            bento.withdraw(token, address(this), to, 0, amount);
        } else {
            bento.transfer(token, address(this), to, amount);
        }
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
        liquidityOptimal[0] = liquidityAmount({
            token: liquidityInputs[0].token,
            amount: liquidityInputs[0].amountDesired
        });
        liquidityOptimal[1] = liquidityAmount({
            token: liquidityInputs[1].token,
            amount: liquidityInputs[1].amountDesired
        });

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

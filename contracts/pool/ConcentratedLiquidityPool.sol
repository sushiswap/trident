// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../interfaces/IPool.sol";
import "../interfaces/IBentoBox.sol";
import "../interfaces/ITridentCallee.sol";
import "./TridentNFT.sol";
import "./MirinERC20.sol";
import "../libraries/MirinMath.sol";
import "../libraries/TickMath.sol";
import "hardhat/console.sol";
import "../deployer/MasterDeployer.sol";

library ConcentratedMath {
    function log_2 (uint256 x) internal pure returns (uint256) {
        unchecked {
            require (x > 0);

            uint256 msb = 0;
            uint256 xc = x;
            if (xc >= 0x10000000000000000) { xc >>= 64; msb += 64; }
            if (xc >= 0x100000000) { xc >>= 32; msb += 32; }
            if (xc >= 0x10000) { xc >>= 16; msb += 16; }
            if (xc >= 0x100) { xc >>= 8; msb += 8; }
            if (xc >= 0x10) { xc >>= 4; msb += 4; }
            if (xc >= 0x4) { xc >>= 2; msb += 2; }
            if (xc >= 0x2) msb += 1;  // No need to shift xc anymore

            uint256 result = msb - 64 << 64;
            uint256 ux = uint256 (uint256 (x)) << uint256 (127 - msb);
            for (uint256 bit = 0x8000000000000000; bit > 0; bit >>= 1) {
                ux *= ux;
                uint256 b = ux >> 255;
                ux >>= 127 + b;
                result += bit * uint256 (b);
            }

            return uint256 (result);
        }
    }

    function ln (uint256 x) internal pure returns (uint256) {
        unchecked {
            require (x > 0);

            return (log_2 (x) * 0xB17217F7D1CF79ABC9E3B39803F2F6AF >> 128);
        }
    }
    
    function pow(uint256 a, uint256 b) internal returns (uint256) { 
        return a**b;
    }
    
    function calcTick(uint256 rp) internal returns (uint256) {
        return ln(rp) * 2 / ln(10001);
    }
    
    function calcSqrtPrice(uint256 i) internal returns (uint256) {
        return pow(10001, i / 2);
    }
}

/// @dev This pool swaps between bento shares. It does not care about underlying amounts.
contract ConcentratedLiquidityPool is MirinERC20, IPool {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

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
    
    int24 public immutable tickSpacing;
    int24 public nearestTick;
    
    uint112 public liquidity;
    uint160 public sqrtPriceX96;

    uint256 public kLast;

    uint128 internal reserve0;
    uint128 internal reserve1;
    
    mapping(int24 => Tick) public ticks;
    struct Tick {
        int24 previousTick;
        int24 nextTick;
        uint128 reserve0;
        uint128 reserve1;
        bool exists; // might not be necessary
    }

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
        (IERC20 tokenA, IERC20 tokenB, uint256 _swapFee, int24 _tickSpacing, uint160 _sqrtPriceX96) = abi.decode(_deployData, (IERC20, IERC20, uint256, int24, uint160));

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
        tickSpacing = _tickSpacing;
        ticks[TickMath.MIN_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), uint128(0), true);
        ticks[TickMath.MAX_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), uint128(0), true);
        nearestTick = TickMath.MIN_TICK;
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
            amount0 += _getAmountOut(amount1, _reserve0 - amount0, _reserve1 - amount1);
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
            
            amountOut = _computeRange(amountIn, true);
            _processSwap(tokenIn, tokenOut, recipient, amountIn, amountOut, context, unwrapBento);

            (uint256 balance0, uint256 balance1) = _balance();
            require(balance0 - _reserve0 >= amountIn, "Insuffficient amount in");

            _update(balance0, balance1 - amountOut);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");

            amountOut = _computeRange(amountIn, true);
            _processSwap(tokenIn, tokenOut, recipient, amountIn, amountOut, context, unwrapBento);

            (uint256 balance0, uint256 balance1) = _balance();
            require(balance1 - _reserve1 >= amountIn, "Insuffficient amount in");

            _update(balance0 - amountOut, balance1);
        }

        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }
    
    function _computeRange(uint256 amountIn, bool token0) internal returns (uint256 delta) {
        /// @dev using sarang's tick cross/swap formula
        uint256 nearestTickReserve0 = ticks[nearestTick].reserve0;
        uint256 nearestTickReserve1 = ticks[nearestTick].reserve1;
        
        uint256 delta_y = amountIn;
        uint256 nearestTickLiquidity = MirinMath.sqrt(nearestTickReserve0 * nearestTickReserve1);
        uint256 delta_sqrt_price = delta_y / nearestTickLiquidity;
        uint256 sqrt_price = MirinMath.sqrt(nearestTickReserve1 / nearestTickReserve0);
        
        uint256 tick_start = ConcentratedMath.calcTick(sqrt_price);
        uint256 tick_finish = ConcentratedMath.calcTick(sqrt_price + delta_sqrt_price);
        uint256 diff = tick_finish - tick_start;
        uint256 delta_x = 0;
        
        for (uint256 i = 0; i < diff; i++) {
            // calculate the delta_sqrt_price
            uint256 tick_sqrt_price = ConcentratedMath.calcSqrtPrice(tick_start + 1);
            delta_sqrt_price = tick_sqrt_price - sqrt_price;
            uint256 inverse_delta_sqrt_price = (1 / sqrt_price) - (1 / tick_sqrt_price);
            
            // check how much y is left to swap
            if (delta_y - (delta_sqrt_price * nearestTickLiquidity) > 0) {
                delta_y -= (delta_sqrt_price * nearestTickLiquidity);
                delta_x += (nearestTickLiquidity * inverse_delta_sqrt_price);
            } else {
                // delta_y is exhausted for the integer value of tick
            }
            
            if (delta_y > 0) {
                delta_sqrt_price = delta_y / nearestTickLiquidity;
                uint256 fractional_tick = ConcentratedMath.calcTick(sqrt_price + delta_sqrt_price);
                tick_sqrt_price = ConcentratedMath.calcSqrtPrice(fractional_tick);
                inverse_delta_sqrt_price = (1 / sqrt_price) - (1 / tick_sqrt_price);
                delta_x += (nearestTickLiquidity * inverse_delta_sqrt_price);
            }
        }
        
        return delta_x;
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

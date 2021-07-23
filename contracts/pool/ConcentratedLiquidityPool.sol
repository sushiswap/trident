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
    function log_2(uint256 x) internal pure returns (uint256) {
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

    function ln(uint256 x) internal pure returns (uint256) {
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
abstract contract ConcentratedLiquidityPool is IPool, TridentNFT {
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
        uint128 reserve0; // to-do consolidate to liquidity?
        uint128 reserve1; // to-do consolidate to liquidity?
        uint128 liquidity; // last range liquidity 
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
    constructor(bytes memory _deployData, address _masterDeployer) TridentNFT() {
        (IERC20 tokenA, IERC20 tokenB, uint256 _swapFee, int24 _tickSpacing, uint160 _sqrtPriceX96) = abi.decode(_deployData, (IERC20, IERC20, uint256, int24, uint160));

        require(address(tokenA) != address(0), "ZERO_ADDRESS");
        require(address(tokenB) != address(0), "ZERO_ADDRESS");
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "INVALID_SWAP_FEE");

        (IERC20 _token0, IERC20 _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxV1(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        tickSpacing = _tickSpacing;
        ticks[TickMath.MIN_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), uint128(0), uint128(0), true);
        ticks[TickMath.MAX_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint128(0), uint128(0), uint128(0), true);
        nearestTick = TickMath.MIN_TICK;
        unlocked = 1;
    }

    function mint(int24 lowerOld, int24 lower, int24 upperOld, int24 upper, address recipient) public lock returns (uint256 liquidity) {
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        
        /// @dev replicating v2-style LP through `TridentNFT` which has erc20-like values in struct (totalSupply, balanceOf)....
        uint112 _rangeReserve0 = tickPools[lower][upper].reserve0; 
        uint112 _rangeReserve1 = tickPools[lower][upper].reserve1; 
        uint256 _totalSupply = tickPools[lower][upper].totalSupply; 
        _mintFee(lower, upper, _rangeReserve0, _rangeReserve1, _totalSupply);

        (uint256 balance0, uint256 balance1) = _balance(); 
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint112 rangeLiquidity = uint112(MirinMath.sqrt(_rangeReserve0 * _rangeReserve0));
        uint112 liquidityToAdd = uint112(MirinMath.sqrt(amount0 * amount1));
        uint256 computed = rangeLiquidity + liquidityToAdd;
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(lower, upper, address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = ((computed - rangeLiquidity) * _totalSupply) / rangeLiquidity;
        }
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(lower, upper, recipient, liquidity);
        _update(balance0, balance1);
        kLast = MirinMath.sqrt(balance0 * balance1);
        
        /// @dev CPCP hooks for gasper's Tick link-listing....
        uint160 priceLower = TickMath.getSqrtRatioAtTick(lower); 
        uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);
        uint160 currentPrice = sqrtPriceX96; // gas savings
      
        if (priceLower < currentPrice && currentPrice < priceUpper) liquidity += uint112(liquidityToAdd);
        tickPools[lower][upper].liquidity += uint112(liquidityToAdd);
        /// @dev temporary range reserve tracking values to make other functions easier to test
        tickPools[lower][upper].reserve0 += uint112(amount0);
        tickPools[lower][upper].reserve1 += uint112(amount1);

        updateLinkedList(lowerOld, lower, upperOld, upper, amount0, ammount1, liquidityToAdd);
        updateNearestTickPointer(lower, upper, nearestTick, currentPrice);
        getAssets(priceLower, priceUpper, currentPrice, liquidityToAdd);
        
        emit Mint(msg.sender, amount0, amount1, recipient);
    }

    function burn(uint256 tokenId, address recipient, bool unwrapBento)
        public
        lock
        returns (liquidityAmount[] memory withdrawnAmounts)
    {
        int24 lower = ranges[tokenId].lower;
        int24 upper = ranges[tokenId].upper;
        /// @dev replicating v2-style LP through `TridentNFT` which has erc20-like values in struct (totalSupply, balanceOf)....
        uint112 _rangeReserve0 = tickPools[lower][upper].reserve0; 
        uint112 _rangeReserve1 = tickPools[lower][upper].reserve1; 
        uint256 _totalSupply = tickPools[lower][upper].totalSupply; 
         _mintFee(lower, upper, _rangeReserve0, _rangeReserve1, _totalSupply);
        
        uint112 rangeLiquidity = uint112(MirinMath.sqrt(_rangeReserve0 * _rangeReserve0));
        uint256 liquidityToBurn = tickPools[lower][upper].balanceOf[address(this)]; 
        uint256 balance0 = tickPools[lower][upper].reserve0;
        uint256 balance1 = tickPools[lower][upper].reserve1;

        uint256 amount0 = (liquidityToBurn * balance0) / _totalSupply;
        uint256 amount1 = (liquidityToBurn * balance1) / _totalSupply;

        _burn(tokenId, address(this), liquidityToBurn);

        _transfer(token0, amount0, recipient, unwrapBento);
        _transfer(token1, amount1, recipient, unwrapBento);

        /// @dev placeholding below price updating for now....
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);
        (balance0, balance1) = _balance();
        _update(balance0, balance1);
        kLast = MirinMath.sqrt(balance0 * balance1);
        
        tickPools[lower][upper].liquidity -= uint112(liquidityToBurn);
        /// @dev temporary range reserve tracking values to make other functions easier to test
        tickPools[lower][upper].reserve0 -= uint112(amount0);
        tickPools[lower][upper].reserve1 -= uint112(amount1);
        
        withdrawnAmounts = new liquidityAmount[](2);
        withdrawnAmounts[0] = liquidityAmount({token: address(token0), amount: amount0});
        withdrawnAmounts[1] = liquidityAmount({token: address(token1), amount: amount1});

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

        if (tokenIn == address(token0)) {
            require(tokenOut == address(token1), "Invalid output token");
            amountIn = balance0 - _reserve0;
            amountOut = _getRangeAmountOut(amountIn, _reserve0, _reserve1);
            _transfer(token1, amountOut, recipient, unwrapBento);
            _update(balance0, balance1 - amountOut);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");
            amountIn = balance1 - _reserve1;
            amountOut = _getRangeAmountOut(amountIn, _reserve1, _reserve0);
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
            
            amountOut = _getRangeAmountOut(amountIn, _reserve0, _reserve1);
            _processSwap(tokenIn, tokenOut, recipient, amountIn, amountOut, context, unwrapBento);

            (uint256 balance0, uint256 balance1) = _balance();
            require(balance0 - _reserve0 >= amountIn, "Insuffficient amount in");

            _update(balance0, balance1 - amountOut);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");

            amountOut = _getRangeAmountOut(amountIn, _reserve1, _reserve0);
            _processSwap(tokenIn, tokenOut, recipient, amountIn, amountOut, context, unwrapBento);

            (uint256 balance0, uint256 balance1) = _balance();
            require(balance1 - _reserve1 >= amountIn, "Insuffficient amount in");

            _update(balance0 - amountOut, balance1);
        }

        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }
    
    function _getRangeAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal returns (uint256 delta) {
        /// @dev using sarang's tick cross/swap formula
        uint256 delta_y = amountIn;
        uint256 liquidity = MirinMath.sqrt(reserveIn * reserveOut);
        uint256 delta_sqrt_price = delta_y / liquidity;
        uint256 sqrt_price = MirinMath.sqrt(reserveIn / reserveOut);
        
        uint256 tick_start = ConcentratedMath.calcTick(sqrt_price);
        uint256 tick_finish = ConcentratedMath.calcTick(sqrt_price + delta_sqrt_price);
        uint256 diff = tick_finish - tick_start;
        uint256 delta_x = 0;
        
        for (uint256 i = 0; i < diff; i++) {
            // calculate the delta_sqrt_price
            uint256 tick_sqrt_price = ConcentratedMath.calcSqrtPrice(tick_start + i + 1);
            delta_sqrt_price = tick_sqrt_price - sqrt_price;
            uint256 inverse_delta_sqrt_price = (1 / sqrt_price) - (1 / tick_sqrt_price);
            
            // check how much y is left to swap
            if (delta_y - (delta_sqrt_price * liquidity) > 0) {
                delta_y -= (delta_sqrt_price * liquidity);
                delta_x += (liquidity * inverse_delta_sqrt_price);
            } else {
            // delta_y is exhausted for the integer value of tick
            }
            
            if (delta_y > 0) {
                delta_sqrt_price = delta_y / liquidity;
                uint256 fractional_tick = ConcentratedMath.calcTick(sqrt_price + delta_sqrt_price);
                tick_sqrt_price = ConcentratedMath.calcSqrtPrice(fractional_tick);
                inverse_delta_sqrt_price = (1 / sqrt_price) - (1 / tick_sqrt_price);
                delta_x += (liquidity * inverse_delta_sqrt_price);
            }
        }
        
        delta = delta_x;
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
        require(balance0 < type(uint128).max && balance1 < type(uint128).max, "OVERFLOW");
        reserve0 = uint128(balance0);
        reserve1 = uint128(balance1);
    }

    function _mintFee(
        int24 lower,
        int24 upper,
        uint128 _reserve0,
        uint128 _reserve1,
        uint256 _totalSupply
    ) internal returns (uint256 computed) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            computed = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
            if (computed > _kLast) {
                // barFee % of increase in liquidity
                // NB It's going to be slightly less than barFee % in reality due to the Math
                uint256 barFee = MasterDeployer(masterDeployer).barFee();
                uint256 liquidity = (_totalSupply * (computed - _kLast) * barFee) / computed / MAX_FEE;
                if (liquidity > 0) {
                    _mint(lower, upper, barFeeTo, liquidity);
                }
            }
        }
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = bento.balanceOf(token0, address(this));
        balance1 = bento.balanceOf(token1, address(this));
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
            amountOut = _getRangeAmountOut(amountIn, _reserve0, _reserve1);
        } else {
            amountOut = _getRangeAmountOut(amountIn, _reserve1, _reserve0);
        }
    }

    /// @dev gasper's link-listing logic for tick updates ****
    function getAssets(uint160 priceLower, uint160 priceUpper, uint160 _sqrtPriceX96, uint112 liquidityAmount) internal {
        uint256 token0amount = 0;
        uint256 token1amount = 0;
        // to-do use the fullmath library here to deal with over flows
        if (priceUpper < _sqrtPriceX96) { // todo, think about edgecases here <= vs <
            // only supply token1 (token1 is Y)
            token1amount = liquidityAmount * uint256(priceUpper - priceLower);
        } else if (_sqrtPriceX96 < priceLower) {
            // only supply token0 (token0 is X)
            token0amount = (liquidityAmount * uint256(priceUpper - priceLower) / priceLower ) / priceUpper;
        } else {
            token0amount = ((uint256(liquidityAmount) << 96) * uint256(priceUpper - _sqrtPriceX96) / _sqrtPriceX96) / priceUpper;
            token1amount = liquidityAmount * uint256(_sqrtPriceX96 - priceLower) / 0x1000000000000000000000000;
        }
    }

    function updateNearestTickPointer(int24 lower, int24 upper, int24 currentNearestTick, uint160 _sqrtPriceX96) internal  {
        int24 actualNearestTick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);
        if (currentNearestTick < lower && lower <= actualNearestTick) currentNearestTick = lower;
        if (currentNearestTick < upper && upper <= actualNearestTick) currentNearestTick = upper;
        nearestTick = currentNearestTick;
    }

    function updateLinkedList(int24 lowerOld, int24 lower, int24 upperOld, int24 upper, uint112 amount0, uint112 amount1, uint112 liquidity) internal {
        require(uint24(lower) % 2 == 0, "Lower even");
        require(uint24(upper) % 2 == 1, "Upper odd");

        if (ticks[lower].exists) {
            ticks[lower].liquidity += liquidity;
        } else {
            Tick storage old = ticks[lowerOld];
            require(old.exists && old.nextTick > lower && lowerOld < lower, "Bad ticks");
            ticks[lower] = Tick(lowerOld, old.nextTick, amount0, amount1, liquidity, true);
            old.nextTick = lower;
        }
        if (ticks[upper].exists) {
            ticks[upper].liquidity += liquidity;
        } else {
            Tick storage old = ticks[upperOld];
            require(old.exists && old.nextTick > upper && upperOld < upper, "Bad ticks");
            ticks[upper] = Tick(upperOld, old.nextTick, amount0, amount1, liquidity, true);
            old.nextTick = upper;
        }
    }
}

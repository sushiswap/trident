// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/TickMath.sol";

pragma solidity ^0.8.2;

contract Cpcp {

  struct Tick {
    int24 previousTick;
    int24 nextTick;
    uint112 liquidity;
    bool exists; // might not be necessary
  }

  mapping(int24 => Tick) public ticks;

  int24 public currentTick;
  
  uint112 public liquidity;

  uint160 public sqrtPriceX96;

  int24 public nearestTick;

  IERC20 public token0;
  
  IERC20 public token1;

  constructor(bytes memory deployData) {

    (IERC20 _token0, IERC20 _token1, uint160 _sqrtPriceX96) = abi.decode(deployData, (IERC20, IERC20, uint160));

    token0 = _token0;
    
    token1 = _token1;

    sqrtPriceX96 = _sqrtPriceX96;

    ticks[TickMath.MIN_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint112(0), true);

    ticks[TickMath.MAX_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint112(0), true);

    nearestTick = TickMath.MIN_TICK;

  }

  function mint(int24 lowerOld, int24 lower, int24 upperOld, int24 upper, uint112 amount) public {

    uint160 priceLower = TickMath.getSqrtRatioAtTick(lower);
    
    uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);

    uint160 currentPrice = sqrtPriceX96;

    if (priceLower < currentPrice && currentPrice < priceUpper) liquidity += amount;

    updateLinkedList(lowerOld, lower, upperOld, upper, amount);

    updateNearestTickPointer(lower, upper, nearestTick, currentPrice);
    
    getAssets(priceLower, priceUpper, currentPrice, amount);

  }

  function getAssets(uint160 priceLower, uint160 priceUpper, uint160 _sqrtPriceX96, uint112 liquidityAmount) internal {

    uint256 token0amount = 0;

    uint256 token1amount = 0;

    if (priceUpper < _sqrtPriceX96) {

      // only supply token1 (token1 is Y)
      token1amount = liquidityAmount * uint256(priceUpper - priceLower);
    
    } else if (priceLower <= _sqrtPriceX96) {

      // only supply token0 (token0 is X)
      token0amount = (liquidityAmount * uint256(priceUpper - priceLower) / priceLower ) / priceUpper;

    } else {

      token1amount = liquidityAmount * uint256(_sqrtPriceX96 - priceLower);

      token0amount = (liquidityAmount * uint256(priceUpper - _sqrtPriceX96) / _sqrtPriceX96) / priceUpper;

    }

    if (token0amount > 0) token0.transferFrom(msg.sender, address(this), token0amount);

    if (token1amount > 0) token1.transferFrom(msg.sender, address(this), token1amount);
    
  }

  function updateNearestTickPointer(int24 lower, int24 upper, int24 currentNearestTick, uint160 _sqrtPriceX96) internal  {

    int24 actualNearestTick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);

    if (currentNearestTick < lower && lower <= actualNearestTick) currentNearestTick = lower;
    
    if (currentNearestTick < upper && upper <= actualNearestTick) currentNearestTick = upper;

    nearestTick = currentNearestTick;

  }

  function updateLinkedList(int24 lowerOld, int24 lower, int24 upperOld, int24 upper, uint112 amount) internal {
    
    require(lower % 2 == 0, "Lower even");

    require(upper % 2 == 1, "Upper odd");

    if (ticks[lower].exists) {
      
      ticks[lower].liquidity += amount;

    } else {
      
      Tick storage old = ticks[lowerOld];
      
      require(old.exists && old.nextTick > lower && lowerOld < lower, "Bad ticks");

      ticks[lower] = Tick(lowerOld, old.nextTick, amount, true);
      
      old.nextTick = lower;

    }

    if (ticks[upper].exists) {
      
      ticks[upper].liquidity += amount;

    } else {
      
      Tick storage old = ticks[upperOld];
      
      require(old.exists && old.nextTick > upper && upperOld < upper, "Bad ticks");

      ticks[upper] = Tick(upperOld, old.nextTick, amount, true);
      
      old.nextTick = upper;

    }
  }

}
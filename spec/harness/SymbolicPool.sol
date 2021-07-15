pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "contracts/interfaces/IPool.sol";
contract SymbolicPool is IPool {


    function swapWithoutContext(address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountIn, uint256 amountOut) external override returns(uint256 finalAmountOut) {
        
    }

    function swapExactIn(address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountIn) external override returns(uint256 finalAmountOut) {

    }

    function swapExactOut(address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountOut) external override {

    }

    function swapWithContext(address tokenIn, address tokenOut, bytes calldata context, address recipient, bool unwrapBento, uint256 amountIn, uint256 amountOut) external override returns(uint256 finalAmountOut) {

    }

    function getOptimalLiquidityInAmounts(liquidityInput[] calldata liquidityInputs) external override returns(liquidityAmount[] memory liquidityOptimal) {

    }

    function mint(address to) external override returns(uint256 liquidity) {

    }
}
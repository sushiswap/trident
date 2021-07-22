pragma solidity ^0.8.2;
pragma abicoder v2;

import "../../contracts/SwapRouter.sol";
import "../../contracts/interfaces/IBentoBox.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapRouterHarness is SwapRouter {
    IERC20 public tokenA;

    constructor(address WETH, IBentoBoxV1 bento)
        SwapRouter(WETH, bento) public { }

    function callExactInputSingle(address tokenIn, address tokenOut, address pool, address recipient, bool unwrapBento, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum) public returns (uint256) {
        ExactInputSingleParams memory exactInputSingleParams;
        exactInputSingleParams = ExactInputSingleParams({tokenIn:tokenIn, tokenOut:tokenOut, pool:pool, recipient:recipient,unwrapBento:unwrapBento,deadline:deadline,amountIn:amountIn,amountOutMinimum:amountOutMinimum});
        return exactInputSingle(exactInputSingleParams);
    }

    function callAddLiquidityUnbalancedSingle(address tokenIn, uint256 amount, address pool,  address to, uint256 deadline,uint256 minliquidity) public returns (uint256) {
        IPool.liquidityInputOptimal[] memory liquidityInput = new IPool.liquidityInputOptimal[](1);
        liquidityInput[0] = IPool.liquidityInputOptimal({token: tokenIn, native : false , amount : amount });
        return addLiquidityUnbalanced(liquidityInput, pool, to, deadline, minliquidity);
    }

    function tokenBalanceOf(address token, address user) public returns (uint256) {
        return IERC20(token).balanceOf(user);
    }
}
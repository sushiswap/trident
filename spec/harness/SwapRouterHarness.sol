pragma solidity ^0.8.2;
pragma abicoder v2;

import "../../contracts/SwapRouter.sol";
import "../../contracts/interfaces/IBentoBox.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapRouterHarness is SwapRouter {
    IERC20 public tokenA;

    constructor(address WETH, IBentoBoxV1 bento)
        SwapRouter(WETH, bento) public { }

    // A wrapper for exactInput
    function callExactInputSingle(address tokenIn, address tokenOut, address pool, address recipient, bool unwrapBento, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum) public returns (uint256) {
        ExactInputSingleParams memory exactInputSingleParams;
        exactInputSingleParams = ExactInputSingleParams({tokenIn:tokenIn, tokenOut:tokenOut, pool:pool, recipient:recipient,unwrapBento:unwrapBento,deadline:deadline,amountIn:amountIn,amountOutMinimum:amountOutMinimum});
        return super.exactInputSingle(exactInputSingleParams);
    }

    // Override with empty function
    function exactInputSingle(ExactInputSingleParams memory params)
        public
        override
        payable
        returns (uint256 amountOut) { }


    function callExactInput(address tokenIn1, address pool1, address tokenIn2, address pool2,
        address tokenOut,
        address recipient,
        bool unwrapBento,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum)
        public
        virtual
        payable
        returns (uint256 amount)
    { }
    /* todo - try to put back
        Path[] memory paths = new Path[](2);
        paths[0] = Path({tokenIn : tokenIn1, pool: pool1});
        paths[1] = Path({tokenIn : tokenIn2, pool: pool2});
        ExactInputParams memory exactInputParams = ExactInputParams({
                path : paths, 
                tokenOut : tokenOut, 
                recipient: recipient,
                unwrapBento : unwrapBento,
                deadline : deadline,
                amountIn : amountIn,
                amountOutMinimum : amountOutMinimum });
        return super.exactInput(exactInputParams);
    } */


    function exactInput(ExactInputParams memory params)
        public
        override
        payable
        returns (uint256 amount)
    { }


    function callExactInputSingleWithNativeToken(address tokenIn, address tokenOut, address pool, address recipient, bool unwrapBento, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum)
        public returns (uint256) {
        ExactInputSingleParams memory exactInputSingleParams;
        exactInputSingleParams = ExactInputSingleParams({tokenIn:tokenIn, tokenOut:tokenOut, pool:pool, recipient:recipient,unwrapBento:unwrapBento,deadline:deadline,amountIn:amountIn,amountOutMinimum:amountOutMinimum});
        return super.exactInputSingleWithNativeToken(exactInputSingleParams);
    }

    function exactInputSingleWithNativeToken(ExactInputSingleParams memory params)
        public
        override
        payable
        returns (uint256 amountOut)
    { }

    //todo - add call function
    function exactInputWithNativeToken(ExactInputParams memory params)
        public
        override
        payable
        returns (uint256 amount)
    { }



    bytes public harnessBytes;
    function callExactInputSingleWithContext(address tokenIn, 
        address tokenOut,
        address pool,
        address recipient,
        bool unwrapBento,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum)
        public
        virtual
        payable
        returns (uint256 amount)
    {
        ExactInputSingleParamsWithContext memory exactInputSingleParamsWithContext;
        exactInputSingleParamsWithContext = ExactInputSingleParamsWithContext({tokenIn:tokenIn, tokenOut:tokenOut, pool:pool, recipient:recipient,unwrapBento:unwrapBento,deadline:deadline,amountIn:amountIn,amountOutMinimum:amountOutMinimum, context: harnessBytes});
        return super.exactInputSingleWithContext(exactInputSingleParamsWithContext);
    }

    function exactInputSingleWithContext(ExactInputSingleParamsWithContext memory params)
        public
        override
        payable
        returns (uint256 amountOut)
    { }


    function callExactInputSingleWithNativeTokenAndContext(address tokenIn, 
        address tokenOut,
        address pool,
        address recipient,
        bool unwrapBento,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum)
        public
        virtual
        payable
        returns (uint256 amountOut)
    {
        ExactInputSingleParamsWithContext memory exactInputSingleParamsWithContext;
        exactInputSingleParamsWithContext = ExactInputSingleParamsWithContext({tokenIn:tokenIn, tokenOut:tokenOut, pool:pool, recipient:recipient,unwrapBento:unwrapBento,deadline:deadline,amountIn:amountIn,amountOutMinimum:amountOutMinimum, context: harnessBytes});
        return super.exactInputSingleWithNativeTokenAndContext(exactInputSingleParamsWithContext);
    }

    function exactInputSingleWithNativeTokenAndContext(ExactInputSingleParamsWithContext memory params)
        public
        override
        payable
        returns (uint256 amountOut)
    {
    }
    function exactInputWithContext(ExactInputParamsWithContext memory params)
        public
        override
        payable
        returns (uint256 amount)
    {
    }
    // A wrapper and override for addLiquidityUnbalance
    function callAddLiquidityUnbalanced(address tokenIn1, uint256 amount1, address tokenIn2, uint256 amount2, address pool,  address to, uint256 deadline,uint256 minliquidity) public returns (uint256) {
        IPool.liquidityInputOptimal[] memory liquidityInput = new IPool.liquidityInputOptimal[](2);
        liquidityInput[0] = IPool.liquidityInputOptimal({token: tokenIn1, native : false , amount : amount1 });
        liquidityInput[1] = IPool.liquidityInputOptimal({token: tokenIn2, native : false , amount : amount2 });
        return super.addLiquidityUnbalanced(liquidityInput, pool, to, deadline, minliquidity);
    }

    // A wrapper and override for addLiquidityUnbalance
    function callAddLiquidityUnbalanced(address tokenIn, uint256 amount, address pool,  address to, uint256 deadline,uint256 minliquidity) public returns (uint256) {
        IPool.liquidityInputOptimal[] memory liquidityInput = new IPool.liquidityInputOptimal[](1);
        liquidityInput[0] = IPool.liquidityInputOptimal({token: tokenIn, native : false , amount : amount });
        return super.addLiquidityUnbalanced(liquidityInput, pool, to, deadline, minliquidity);
    }

    function addLiquidityUnbalanced(
        IPool.liquidityInputOptimal[] memory liquidityInput,
        address pool,
        address to,
        uint256 deadline,
        uint256 minLiquidity
    ) public override returns (uint256 liquidity) { }


    function callAddLiquidityBalanced(
        address tokenIn, 
        uint256 amount,
        address pool,
        address to,
        uint256 deadline
    ) external checkDeadline(deadline) returns (IPool.liquidityAmount[] memory liquidityOptimal, uint256 liquidity) {
        IPool.liquidityInput[] memory liquidityInput = new IPool.liquidityInput[](1);
        liquidityInput[0] = IPool.liquidityInput({token: tokenIn , native : false , amountDesired : amount , amountMin : 0});
        return super.addLiquidityBalanced(liquidityInput, pool, to, deadline);
    }

    function addLiquidityBalanced(
        IPool.liquidityInput[] memory liquidityInput,
        address pool,
        address to,
        uint256 deadline
    ) public override returns (IPool.liquidityAmount[] memory liquidityOptimal, uint256 liquidity) {

    }
    
    function callBurnLiquidity(
       address pool,
       address token1,
       address token2,
       address to,
       bool unwrapBento,
       uint256 deadline,
       uint256 liquidity
    ) external checkDeadline(deadline) {
        IPool.liquidityAmount[] memory liquidityAmount = new IPool.liquidityInput[](2);
        liquidityAmount[0] = IPool.liquidityAmount(token1, 0);
        liquidityAmount[1] = IPool.liquidityAmount(token2, 0);
        return super.burnLiquidity(pool, to, unwrapBento, deadline, liquidity, liquidityAmount);
    }

    function burnLiquidity(
        address pool,
        address to,
        bool unwrapBento,
        uint256 deadline,
        uint256 liquidity,
        IPool.liquidityAmount[] memory minWithdrawals
    ) external override {

    }

    function complexPath(ComplexPathParams memory params) public override payable 
     { }
    function tokenBalanceOf(address token, address user) public returns (uint256) {
        return IERC20(token).balanceOf(user);
    }

    function ethBalance(address user) public returns (uint256) {
        return user.balance;
    }

}
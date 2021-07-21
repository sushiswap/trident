pragma solidity ^0.8.2;
pragma abicoder v2;

import "../../contracts/SwapRouter.sol";
import "../../contracts/interfaces/IBentoBox.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract SwapRouterHarness is SwapRouter {
    // fields of the SwapRouter structs
    bytes public contextHarness;
    address public tokenInHarness;
    address public tokenOutHarness;
    address public poolHarness;
    address public recipientHarness;
    bool public unwrapBentoHarness;
    uint256 public deadlineHarness;
    uint256 public amountInHarness;
    uint256 public amountOutMinimumHarness;
    bool public preFundedHarness;
    uint64 public balancePercentageHarness;
    uint256 public toHarness;
    uint256 public minAmountHarness;

    IERC20 public tokenA;

    constructor(address WETH, IBentoBoxV1 bento)
        SwapRouter(WETH, bento) public { }

    function exactInputSingle(ExactInputSingleParams calldata params)
        public
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        require(params.deadline == deadlineHarness);
        require(params.tokenIn == tokenInHarness);
        require(params.tokenOut == tokenOutHarness);
        require(params.recipient == recipientHarness);
        require(params.unwrapBento == unwrapBentoHarness);
        require(params.amountIn == amountInHarness);
        require(params.amountOutMinimum == amountOutMinimumHarness);
        require(params.pool == poolHarness);

        super.exactInputSingle(params);
    }

    /*function exactInput(ExactInputParams memory params) public payable override checkDeadline(params.deadline) returns (uint256 amount) 
    {
        require(params.deadline == deadlineHarness);
        require(params.path[0].tokenIn == tokenInHarness);
        require(params.path[0].pool == poolHarness);

        super.exactInput(params);
    }

    function exactInputSingleWithNativeToken(ExactInputSingleParams calldata params)
        public
        payable
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        require(params.tokenIn == tokenInHarness);
        require(params.tokenOut == tokenOutHarness);
        require(params.recipient == recipientHarness);
        require(params.unwrapBento == unwrapBentoHarness);
        require(params.amountIn == amountInHarness);
        require(params.pool == poolHarness);

        super.exactInputSingleWithNativeToken(params);
    }

    function exactInputWithNativeToken(ExactInputParams memory params)
        public
        payable
        checkDeadline(params.deadline)
        returns (uint256 amount)
    {
        require(params.deadline == deadlineHarness);
        require(params.path[0].tokenIn == tokenInHarness);
        require(params.path[0].pool == poolHarness);

        super.exactInputWithNativeToken(params);
    }

    function exactInputSingleWithContext(ExactInputSingleParamsWithContext calldata params)
        public
        payable
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        require(params.tokenIn == tokenInHarness);
        require(params.tokenOut == tokenOutHarness);
        require(params.context == contextHarness);
        require(params.recipient == recipientHarness);
        require(params.unwrapBento == unwrapBentoHarness);
        require(params.amountIn == amountInHarness);
        require(params.pool == poolHarness);

        super.exactInputSingleWithContext(params);
    }*/


    function callAddLiquidityUnbalancedSingle(address tokenIn, uint256 amount, address pool,  address to, uint256 deadline,uint256 minliquidity) public returns (uint256) {
        IPool.liquidityInputOptimal[] memory liquidityInput = new IPool.liquidityInputOptimal[](1);
        liquidityInput[0] = IPool.liquidityInputOptimal({token: tokenIn, native : false , amount : amount });
        return  addLiquidityUnbalanced(liquidityInput, pool, to, deadline, minliquidity);
    }


    function tokenBalanceOf(address token, address user) public returns (uint256) {
        return IERC20(token).balanceOf(user);
    }
}
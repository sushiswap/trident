pragma solidity ^0.8.2;
pragma abicoder v2;

import "../../contracts/SwapRouter.sol";

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

    constructor(address _WETH, address _masterDeployer, address _bento)
        SwapRouter(_WETH, _masterDeployer, _bento) public { }

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
}
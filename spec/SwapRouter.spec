/*
    This is a specification file for smart contract verification
    with the Certora prover. For more information,
	visit: https://www.certora.com/

    This file is run with scripts/...
	Assumptions:
*/

using SimpleBentoBox as bento
using DummyERC20A as tokenA

////////////////////////////////////////////////////////////////////////////
//                                Methods                                 //
////////////////////////////////////////////////////////////////////////////
/*
    Declaration of methods that are used in the rules.
    envfree indicate that the method is not dependent on the environment (msg.value, msg.sender).
    Methods that are not declared here are assumed to be dependent on env.
*/

methods {
    // global variables use to create SwapRouter structs
    contextHarness() returns (bytes) envfree
    tokenInHarness() returns (address) envfree
    tokenOutHarness() returns (address) envfree
    poolHarness() returns (address) envfree
    recipientHarness() returns (address) envfree
    unwrapBentoHarness() returns (bool) envfree
    deadlineHarness() returns (uint256) envfree
    amountInHarness() returns (uint256) envfree
    amountOutMinimumHarness() returns (uint256) envfree
    preFundedHarness() returns (bool) envfree
    balancePercentageHarness() returns (uint64) envfree
    toHarness() returns (uint256) envfree
    minAmountHarness() returns (uint256) envfree

    deposit(address,address,address,uint256,uint256) returns (uint256 amountOut, uint256 shareOut) => NONDET;

    // signatures
    exactInputSingle((address, address, address, address, bool, uint256, uint256, uint256))

    // bentobox
    toAmount(address token, uint256 share, bool roundUp)
        returns (uint256) envfree => DISPATCHER(true)
    toShare(address token, uint256 amount, bool roundUp) 
        returns (uint256) envfree => DISPATCHER(true)
    transer(address, address, address, uint256) envfree => DISPATCHER(true)
    registerProtocol() => NONDET

    // ERC20
    balanceOf(address) returns (uint256) => DISPATCHER(true)
    transfer(address, uint256) => DISPATCHER(true) 
    permit(address from, address to, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) => NONDET

    //IPool
    swapWithoutContext(address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountIn, uint256 amountOut) returns (uint256) => DISPATCHER(true)
    swapExactIn(address tokenIn,address tokenOut,address recipient,bool unwrapBento,uint256 amountIn) returns (uint256) => DISPATCHER(true)
    swapExactOut(address tokenIn,address tokenOut,address recipient,bool unwrapBento,uint256 amountOut) => DISPATCHER(true)
    swapWithContext(address tokenIn,address tokenOut,bytes context,address recipient,bool unwrapBento,uint256 amountIn,uint256 amountOut) returns (uint256) => DISPATCHER(true)
    getOptimalLiquidityInAmounts((address,bool,uint256,uint256)[] liquidityInputs) returns((address,uint256)[]) => DISPATCHER(true)
    mint(address to) returns (uint256 liquidity) => DISPATCHER(true)

}

// This is just to check that the harness is working correctly
/*rule exactInputSingleCanBeHarnessed() {
    env e;

    calldataarg args;

    uint256 _minAmount = minAmountHarness();
    uint256 _deadline = deadlineHarness();

    exactInputSingle(e, args);

    uint256 minAmount_ = minAmountHarness();
    uint256 deadline_ = deadlineHarness();

    assert _minAmount < minAmount_ && _deadline < deadline_;
}*/

invariant swapRouterTokenBalanceShouldBeZero(env e)
    tokenA.balanceOf(e, currentContract) == 0

rule swapRouterBalanceShouldBeZero(method f) filtered { f -> f.selector != complexPath((uint256,(address,address,address,bool,uint256,bytes)[],(address,address,address,uint64,bytes)[],(address,address,bool,uint256)[])).selector } {
    env e;
    calldataarg args;

    require(bento.balanceOf(e,tokenA,currentContract) == 0);

    f(e,args);

    assert bento.balanceOf(e,tokenA,currentContract) == 0;
}
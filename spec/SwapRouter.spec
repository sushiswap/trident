/*
    This is a specification file for smart contract verification
    with the Certora prover. For more information,
	visit: https://www.certora.com/

    This file is run with scripts/...
	Assumptions:
*/

using SimpleBentoBox as bento
using DummyERC20A as tokenA
using SymbolicPool as pool

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

    // signatures
    exactInputSingle((address, address, address, address, bool, uint256, uint256, uint256))

    // bentobox
    toAmount(address token, uint256 share, bool roundUp)
        returns (uint256) envfree => DISPATCHER(true)
    toShare(address token, uint256 amount, bool roundUp) 
        returns (uint256) envfree => DISPATCHER(true)
    transfer(address token, address from, address to, uint256 shares) envfree => DISPATCHER(true)
    deposit(address, address, address, uint256, uint256) returns (uint256 amountOut, uint256 shareOut) => DISPATCHER(true)
    balanceOf(address token, address user) returns (uint256) envfree => DISPATCHER(true)
    registerProtocol() => NONDET


    // ERC20
    pool.balanceOf(address) returns (uint256) envfree => DISPATCHER(true)
    transfer(address, uint256) => DISPATCHER(true) 
    transferFrom(address, address, uint256) => DISPATCHER(true) 
    permit(address from, address to, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) => NONDET

    //IPool
    swapWithContext(address tokenIn, address tokenOut, bytes context, address recipient, bool unwrapBento, uint256 amountIn) returns (uint256) => DISPATCHER(true)
    swapWithoutContext(address tokenIn, address tokenOut, address recipient, bool unwrapBento) returns (uint256) => DISPATCHER(true)
    getOptimalLiquidityInAmounts((address,bool,uint256,uint256)[] liquidityInputs) returns((address,uint256)[]) => DISPATCHER(true)
    mint(address to) returns (uint256) => DISPATCHER(true)
    burn(address to, bool unwrapBento) => DISPATCHER(true)
    burnLiquiditySingle(address tokenOut, address to, bool unwrapBento) returns (uint256 amount) => DISPATCHER(true)


    // Symbolic Pool helper
    pool.tokensLength() returns (uint256) envfree
    pool.tokens(uint256 i) returns (address) envfree
    pool.hasToken(address) returns (bool) envfree
    pool.reserves(address token) returns (uint256) envfree
    pool.isStable() returns (bool) envfree

    tokenBalanceOf(address, address) returns (uint256) envfree
    
}

// The total amount of tokens user holds: in the native token and inside bentobox
definition allTokenAssets(address token, address user) returns mathint = 
        tokenBalanceOf(token,user) + bento.toAmount(token,bento.balanceOf(token,user),false);


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

/*invariant swapRouterTokenBalanceShouldBeZero(env e)
    tokenA.balanceOf(e, currentContract) == 0

rule swapRouterBalanceShouldBeZero(method f) filtered { f -> f.selector != complexPath((uint256,(address,address,address,bool,uint256,bytes)[],(address,address,address,uint64,bytes)[],(address,address,bool,uint256)[])).selector } {
    env e;
    calldataarg args;

    require(bento.balanceOf(e,tokenA,currentContract) == 0);

    f(e,args);

    assert bento.balanceOf(e,tokenA,currentContract) == 0;
    
}*/

rule inverseOfSwapping() {
    env e;
    calldataarg args;

    address _tokenIn = tokenInHarness();
    address tokenOut_ = tokenOutHarness();

    uint256 _amountOut = exactInputSingle(e, args);

    _tokenIn = tokenOutHarness();
    tokenOut_ = tokenInHarness();

    uint256 amountOut_ = exactInputSingle(e, args);

    assert _amountOut != amountOut_;
}
/*
rule sanity(method f) {
    env e;
    calldataarg args;
    f(e,args);
    assert(false);
}
*/




rule integrityOfAddLiquidity(address token, uint256 x, uint256 amount) {
    env e;
    uint256 deadline;
    uint256 minLiquidity;
    address user = e.msg.sender;
    
    require token != pool; 
    require user != bento && user != pool && user != currentContract;
    require pool.hasToken(token);
    // pool is at a stable state 
    require pool.isStable();
   
    require amount == x * 2 ; //just to avoid round by 1 


    uint256 nativeBalance = tokenBalanceOf(token,user);
    uint256 bentoBalance = bento.balanceOf(token,user);
    require (nativeBalance < max_uint64 && bentoBalance < max_uint64 );
    mathint userTokenBalanceBefore = tokenBalanceOf(token,user) + bento.toAmount(token,bento.balanceOf(token,user),false);
    uint256 poolTokenBalanceBefore =  bento.balanceOf(token, pool);
    uint256 userLiquidityBalanceBefore = pool.balanceOf(user);
    uint256 liquidity = callAddLiquidityUnbalancedSingle(e, token, amount, pool, user, deadline, minLiquidity);
    
    mathint userTokenBalanceAfter = tokenBalanceOf(token,user) + bento.toAmount(token,bento.balanceOf(token,user),false);
    uint256 poolTokenBalanceAfter =   bento.balanceOf(token, pool);
    uint256 userLiquidityBalanceAfter = pool.balanceOf(user);

    assert userTokenBalanceAfter == userTokenBalanceBefore - amount;
    assert poolTokenBalanceAfter == poolTokenBalanceBefore + bento.toShare(token,amount,false);
    assert userLiquidityBalanceAfter == userLiquidityBalanceBefore + liquidity;

    assert liquidity > 0 <=> amount > 0;
    assert liquidity >= minLiquidity;
}


rule inverseOfMintAndBurnSingle(address token, uint256 amount) {
    env e;
    uint256 deadline;
    uint256 minLiquidity;
    address user = e.msg.sender;
    

    require(pool.tokensLength() == 1 );
    require token == pool.tokens(0);
       
    require token != pool; 
    require user != bento && user != pool && user != currentContract;
    //require token == pool.tokens(0);
    // pool is at a stable state 
    require pool.isStable();

    uint256 userTokenBalanceBefore = tokenBalanceOf(token, e.msg.sender);
    uint256 liquidity = callAddLiquidityUnbalancedSingle(e, token, amount, pool, e.msg.sender, deadline, minLiquidity);
    burnLiquiditySingle(e, pool, token, e.msg.sender, false, deadline, liquidity, 0);
    uint256 userTokenBalanceAfter = tokenBalanceOf(token, e.msg.sender);
    assert( userTokenBalanceAfter == userTokenBalanceBefore);

}

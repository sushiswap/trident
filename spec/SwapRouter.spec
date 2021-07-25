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
    // signatures
    exactInputSingle((address, address, address, address, bool, uint256, uint256, uint256))

    // bentobox
    toAmount(address token, uint256 share, bool roundUp)
        returns (uint256) envfree => DISPATCHER(true)
    toShare(address token, uint256 amount, bool roundUp) 
        returns (uint256) envfree => DISPATCHER(true)
    transfer(address token, address from, address to, uint256 shares) envfree => DISPATCHER(true)
    deposit(address, address, address, uint256, uint256) returns (uint256 amountOut, uint256 shareOut) => DISPATCHER(true)
    bento.balanceOf(address token, address user) returns (uint256) envfree => DISPATCHER(true)
    registerProtocol() => NONDET


    // ERC20
    transfer(address, uint256) => DISPATCHER(true) 
    transferFrom(address, address, uint256) => DISPATCHER(true) 
    permit(address from, address to, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) => NONDET
    totalSupply() => DISPATCHER(true)

    //IPool
    swapWithContext(address tokenIn, address tokenOut, bytes context, address recipient, bool unwrapBento, uint256 amountIn) returns (uint256) => DISPATCHER(true)
    swapWithoutContext(address tokenIn, address tokenOut, address recipient, bool unwrapBento) returns (uint256) => DISPATCHER(true)
    getOptimalLiquidityInAmounts((address,bool,uint256,uint256)[] liquidityInputs) returns((address,uint256)[]) => DISPATCHER(true)
    mint(address to) returns (uint256) => DISPATCHER(true)
    burn(address to, bool unwrapBento) => DISPATCHER(true)
    burnLiquiditySingle(address tokenOut, address to, bool unwrapBento) returns (uint256 amount) => DISPATCHER(true)


    // Symbolic Pool helper
    pool.balanceOf(address) returns (uint256) envfree => DISPATCHER(true)
    pool.getBalanceOfToken(uint256) returns (uint256) envfree
    pool.getReserveOfToken(uint256) returns (uint256) envfree
    pool.tokensLength() returns (uint256) envfree
    pool.getToken(uint256 i) returns (address) envfree
    pool.hasToken(address) returns (bool) envfree
    pool.reserves(address token) returns (uint256) envfree
    pool.isBalanced() returns (bool) envfree
    pool.rates(address,address) returns (uint256) envfree

    
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

rule swapRouterTokenBalanceShouldBeZero(method f) {
    env e;
    calldataarg args;
    require e.msg.sender != bento && e.msg.sender != pool && e.msg.sender != currentContract;
    
    require tokenA.balanceOf(e, currentContract) == 0;
    require ethBalance(e,currentContract) == 0;
    require pool.isBalanced();

    address to;
    address tokenIn; 
    address tokenOut; 
    address recipient;
    bool unwrapBento;
    uint256 amount; 
    uint256 min;

    require recipient != currentContract;
    callFunction(e.msg.sender, f, tokenIn, tokenOut, pool, recipient, unwrapBento, amount, min);

    assert tokenA.balanceOf(e, currentContract) == 0;
    assert ethBalance(e,currentContract) == 0;
}

rule swapRouterBalanceShouldBeZero(method f) filtered { f -> f.selector != complexPath((uint256,(address,address,address,bool,uint256,bytes)[],(address,address,address,uint64,bytes)[],(address,address,bool,uint256)[])).selector } {
    env e;
    calldataarg args;
    require e.msg.sender != bento && e.msg.sender != pool && e.msg.sender != currentContract;

    require(bento.balanceOf(tokenA,currentContract) == 0);

    f(e,args);

    assert bento.balanceOf(tokenA,currentContract) == 0;    
}

rule inverseOfSwapping(address tokenIn, address tokenOut, uint256 amountIn) {
   
    env e;
    address recipient;
    bool unwrapBento;
    uint256 deadline;
    uint256 amountOutMinimum;
    

    
    require(pool.rates(tokenIn,tokenOut) == 1);
    require(pool.rates(tokenOut,tokenIn) == 1);

    address user = e.msg.sender;
    require tokenIn != pool && tokenOut != pool; 
    require user != bento && user != pool && user != currentContract;
    // pool is at a stable state 
    require pool.isBalanced();
    require pool.getToken(0) == tokenIn;
    require pool.getToken(1) == tokenOut;
    require tokenIn != tokenOut;

    uint256 amountInToOut = callExactInputSingle(e, tokenIn, tokenOut, pool, pool, unwrapBento, deadline, amountIn, amountOutMinimum);
    uint256 amountOutToIn = callExactInputSingle(e, tokenOut, tokenIn, pool, recipient, unwrapBento, deadline, amountInToOut, amountOutMinimum);

    assert amountOutToIn == amountIn;
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
    require pool.isBalanced();
   
    require amount == x * 2 ; //just to avoid round by 1 


    uint256 nativeBalance = tokenBalanceOf(token, user);
    uint256 bentoBalance = bento.balanceOf(token, user);
    require (nativeBalance < max_uint64 && bentoBalance < max_uint64 );
    mathint userTokenBalanceBefore = tokenBalanceOf(token, user) + bento.toAmount(token, bento.balanceOf(token, user), false);
    uint256 poolTokenBalanceBefore =  bento.balanceOf(token, pool);
    uint256 userLiquidityBalanceBefore = pool.balanceOf(user);
    uint256 liquidity = callAddLiquidityUnbalanced(e, token, amount, pool, user, deadline, minLiquidity);
    
    mathint userTokenBalanceAfter = tokenBalanceOf(token, user) + bento.toAmount(token, bento.balanceOf(token, user), false);
    uint256 poolTokenBalanceAfter =   bento.balanceOf(token, pool);
    uint256 userLiquidityBalanceAfter = pool.balanceOf(user);

    assert userTokenBalanceAfter == userTokenBalanceBefore - amount;
    assert poolTokenBalanceAfter == poolTokenBalanceBefore + bento.toShare(token, amount, false);
    assert userLiquidityBalanceAfter == userLiquidityBalanceBefore + liquidity;

    assert liquidity > 0 <=> amount > 0;
    assert liquidity >= minLiquidity;
}


rule inverseOfMintAndBurnSingle(address token, uint256 amount) {
    env e;
    uint256 deadline;
    uint256 minLiquidity;
    address user = e.msg.sender;
    
    require pool.hasToken(token);
       
    require token != pool; 
    require user != bento && user != pool && user != currentContract;
    // pool is at a stable state 
    require pool.isBalanced();

    uint256 userTokenBalanceBefore = tokenBalanceOf(token, e.msg.sender);
    uint256 liquidity = callAddLiquidityUnbalanced(e, token, amount, pool, e.msg.sender, deadline, minLiquidity);
    burnLiquiditySingle(e, pool, token, e.msg.sender, false, deadline, liquidity, 0);
    uint256 userTokenBalanceAfter = tokenBalanceOf(token, e.msg.sender);
    assert( userTokenBalanceAfter == userTokenBalanceBefore);

}


rule noChangeToOther(method f, address token, address other) {
    env e;
    calldataarg args;
    require e.msg.sender != bento && e.msg.sender != pool && e.msg.sender != currentContract;
    
    require e.msg.sender != other && bento != other && other != pool && other != currentContract;

    uint256 native = tokenBalanceOf(token, other);
    uint256 inBento  = bento.balanceOf(token, other);
    uint256 eth = ethBalance(e, other);
    uint256 liquidity = pool.balanceOf(other);

    f(e,args);

    assert  tokenBalanceOf(token, other) == native &&
            bento.balanceOf(token, other) == inBento &&
            ethBalance(e, other) == eth  &&
            pool.balanceOf(other) == liquidity ;
}


////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////

function callFunction(address msgSender, method f,
            address tokenIn, address tokenOut, address _pool, address recipient, bool unwrapBento, uint256 amount, uint256 min) {
    env e;
    require e.msg.sender == msgSender;
 /*   uint256 deadline;

    if (f.selector == callAddLiquidityUnbalanced(address,uint256,address,address,uint256,uint256).selector ) {
        callAddLiquidityUnbalanced(e, tokenIn, amount, _pool, recipient, deadline, min);
    }
    else if (f.selector == callAddLiquidityBalanced(address,uint256,address,address,uint256).selector ) {
        callAddLiquidityBalanced(e, tokenIn, amount, _pool, recipient, deadline);
    }
    else if (f.selector == callExactInputSingle(address,address,address,address,bool,uint256,uint256,uint256).selector ){
        callExactInputSingle(e, tokenIn, tokenOut, _pool, recipient, unwrapBento, deadline, amount, min);
    }
    else if (f.selector == callExactInput(address,address,address,address,address,address,bool,uint256,uint256,uint256).selector) {
        address tokenIn2;
        address pool2;
        callExactInput(e, tokenIn, _pool, tokenIn2, pool2, tokenOut, recipient, unwrapBento, deadline, amount, min);
    }
    else { */
        calldataarg args;
        f(e, args);
    //}

}
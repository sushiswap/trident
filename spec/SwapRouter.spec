/*
    This is a specification file for smart contract verification
    with the Certora prover. For more information,
	visit: https://www.certora.com/

    This file is run with scripts/...
	Assumptions:
*/

using SimpleBentoBox as bento
using DummyERC20A as tokenA
using DummyERC20B as tokenB
using DummyWeth as tokenWeth
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
    bento.toAmount(address token, uint256 share, bool roundUp)
        returns (uint256) envfree 
    bento.toShare(address token, uint256 amount, bool roundUp) 
        returns (uint256) envfree 
    bento.transfer(address token, address from, address to, uint256 shares)  
    bento.deposit(address, address, address, uint256, uint256) returns (uint256 amountOut, uint256 shareOut) 
    bento.balanceOf(address token, address user) returns (uint256) envfree 
    //for solidity calls 
    toAmount(address token, uint256 share, bool roundUp) returns (uint256)  => DISPATCHER(true)
    toShare(address token, uint256 amount, bool roundUp) returns (uint256)  => DISPATCHER(true)
    transfer(address token, address from, address to, uint256 shares)  => DISPATCHER(true) 
    deposit(address, address, address, uint256, uint256) returns (uint256 amountOut, uint256 shareOut) => DISPATCHER(true) 
    balanceOf(address token, address user) returns (uint256) => DISPATCHER(true)

    registerProtocol() => NONDET


    // ERC20
    transfer(address, uint256) => DISPATCHER(true) 
    transferFrom(address, address, uint256) => DISPATCHER(true) 
    permit(address from, address to, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) => NONDET
    totalSupply() => DISPATCHER(true)
    balanceOf(address) returns (uint256) => DISPATCHER(true)
    permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, 
                    uint8 v, bytes32 r, bytes32 s) => NONDET

    // WETH
    //withdraw(uint256) => DISPATCHER(true)

    //IPool
    swapWithContext(address tokenIn, address tokenOut, bytes context, address recipient, bool unwrapBento, uint256 amountIn) returns (uint256) => DISPATCHER(true)
    swapWithoutContext(address tokenIn, address tokenOut, address recipient, bool unwrapBento) returns (uint256) => DISPATCHER(true)
    getOptimalLiquidityInAmounts((address,bool,uint256,uint256)[] liquidityInputs) returns((address,uint256)[]) => DISPATCHER(true)
    mint(address to) returns (uint256) => DISPATCHER(true)
    burn(address to, bool unwrapBento) => DISPATCHER(true)
    burnLiquiditySingle(address tokenOut, address to, bool unwrapBento) returns (uint256 amount) => DISPATCHER(true)


    // Symbolic Pool helper
    pool.balanceOf(address) returns (uint256) envfree 
    pool.getReserveOfToken(address) returns (uint256) envfree
    pool.reserves(address token) returns (uint256) envfree
    pool.isBalanced() returns (bool) envfree
    pool.rates(address,address) returns (uint256) envfree
    pool.token0() returns (address) envfree
    pool.token1() returns (address) envfree
    pool.token2() returns (address) envfree

    
    tokenBalanceOf(address, address) returns (uint256) envfree
    
}

function setupPoolAndMsgSender(address sender) {
    require pool.token0() == tokenA || pool.token0() == tokenWeth;
    require pool.token1() == tokenB || pool.token1() == tokenWeth;
    require pool.token2() == tokenA || pool.token2() == tokenB || pool.token2() == tokenWeth;
    require pool.token0() !=  pool.token1() && pool.token1() !=  pool.token2() &&
            pool.token0() !=  pool.token2();
    require sender != bento && sender != pool && sender != currentContract;
}



rule swapRouterTokenBalanceShouldBeZero(method f) filtered {f -> !f.isView && !f.isFallback  } {
    env e;
    calldataarg args;
    setupPoolAndMsgSender(e.msg.sender);

    require pool.isBalanced();
    require tokenA.balanceOf(e, currentContract) == 0;
    //require ethBalance(e,currentContract) == 0;
    require bento.balanceOf(tokenA,currentContract) == 0;
    

    address tokenIn; 
    address tokenOut; 
    address recipient;
    bool unwrapBento;
    uint256 amount; 
    uint256 min;

    require recipient != currentContract && recipient != pool;
    callFunction(e.msg.sender, f, tokenIn, tokenOut, pool, recipient, unwrapBento, amount, min);

    assert tokenA.balanceOf(e, currentContract) == 0;
    //assert ethBalance(e,currentContract) == 0;
    assert bento.balanceOf(tokenA,currentContract) == 0;    
}

rule inverseOfSwapping(address tokenIn, address tokenOut, uint256 amountIn) {
   
    env e;
    address user = e.msg.sender;
    
    address recipient;
    bool unwrapBento;
    uint256 deadline;
    uint256 amountOutMinimum;
    

    setupPoolAndMsgSender(user);
    require tokenIn==tokenA || tokenIn==tokenB || tokenIn==tokenWeth;
    require tokenOut==tokenA || tokenOut==tokenB || tokenOut==tokenWeth;
    require(pool.rates(tokenIn,tokenOut) == 1);
    require(pool.rates(tokenOut,tokenIn) == 1);

    // pool is at a stable state 
    require pool.isBalanced();
    
    uint256 amountInToOut = callExactInputSingle(e, tokenIn, tokenOut, pool, pool, unwrapBento, deadline, amountIn, amountOutMinimum);

    uint256 amountOutToIn = callExactInputSingle(e, tokenOut, tokenIn, pool, recipient, unwrapBento, deadline, amountInToOut, amountOutMinimum);

    uint256 epsilon = 1;
    assert amountOutToIn >= amountIn - epsilon && 
            amountOutToIn <= amountIn + epsilon;
}



rule integrityOfAddLiquidity(address token, uint256 x, uint256 amount) {
    env e;
    uint256 deadline;
    uint256 minLiquidity;
    address user = e.msg.sender;
    
    setupPoolAndMsgSender(user);
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

/* 

passing https://vaas-stg.certora.com/output/23658/3ab8750e04f4fdf4a35f/?anonymousKey=c5a8b48db3924b393fed0967334143f31f4dd089 
*/
rule inverseOfMintAndBurnSingle(address token, uint256 amount) {
    env e;
    uint256 deadline;
    uint256 minLiquidity;
    address user = e.msg.sender;
    
    setupPoolAndMsgSender(user);   
    
    // pool is at a stable state 
    poolHasToken(token);
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
    address user = e.msg.sender;
    
    setupPoolAndMsgSender(user);

    require user != other && bento != other && other != pool && other != currentContract;

    uint256 native = tokenBalanceOf(token, other);
    uint256 inBento  = bento.balanceOf(token, other);
    uint256 eth = ethBalance(e, other);
    uint256 liquidity = pool.balanceOf(other);

    address tokenIn; 
    address tokenOut; 
    address recipient;
    bool unwrapBento;
    uint256 amount; 
    uint256 min;

    require recipient != other;
    callFunction(e.msg.sender, f, tokenIn, tokenOut, pool, recipient, unwrapBento, amount, min);


    assert  tokenBalanceOf(token, other) == native &&
            bento.balanceOf(token, other) == inBento &&
            ethBalance(e, other) == eth  &&
            pool.balanceOf(other) == liquidity ;
}


rule validityOfUnwrapBento(address token, method f) {
    address tokenIn; 
    address tokenOut; 
    address recipient;
    bool unwrapBento;
    uint256 amount; 
    uint256 min;
    address user; 

    
    setupPoolAndMsgSender(user);
    require unwrapBento == true;
    require recipient != currentContract;
    uint256 before = bento.balanceOf(token, user);
    callFunction(user, f, tokenIn, tokenOut, pool, recipient, unwrapBento, amount, min);
    assert bento.balanceOf(token, user) == before;
}

////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////

function callFunction(address msgSender, method f,
            address tokenIn, address tokenOut, address _pool, address recipient, bool unwrapBento, uint256 amount, uint256 min) {
    env e;
    require e.msg.sender == msgSender;
    uint256 deadline;

    if (f.selector == callAddLiquidityUnbalanced(address,uint256,address,address,uint256,uint256).selector ) {
        callAddLiquidityUnbalanced(e, tokenIn, amount, _pool, recipient, deadline, min);
    }
    else if(f.selector == callExactInputSingleWithNativeToken(address,address,address,address,bool,uint256,uint256,uint256).selector) {
        callExactInputSingleWithNativeToken(e, tokenIn, tokenOut, _pool, recipient, unwrapBento, deadline, amount, min);
    }
    else if(f.selector == callExactInputSingleWithContext(address,address,address,address,bool,uint256,uint256,uint256).selector) {
        callExactInputSingleWithContext(e, tokenIn, tokenOut, _pool, recipient, unwrapBento, deadline, amount, min);
    }
    else if(f.selector == callExactInputSingleWithNativeTokenAndContext(address,address,address,address,bool,uint256,uint256,uint256).selector) {
        callExactInputSingleWithNativeTokenAndContext(e, tokenIn, tokenOut, _pool, recipient, unwrapBento, deadline, amount, min);
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
    else if (f.selector == burnLiquiditySingle(address,address,address,bool,uint256,uint256,uint256).selector) {
        burnLiquiditySingle(e, _pool, tokenOut, recipient, unwrapBento, deadline, amount, min);
    }
    else if (f.selector == depositToBentoBox(address,uint256,address).selector) {
        depositToBentoBox(e, tokenIn, amount, recipient);
    }
    else if (f.selector == sweepBentoBoxToken(address,uint256,address).selector) {
        sweepBentoBoxToken(e, tokenIn, amount, recipient);
    }
    else if (f.selector == sweepNativeToken(address,uint256,address).selector) {
        sweepNativeToken(e, tokenIn, amount, recipient);
    }
    
    
    else { 
        calldataarg args;
        f(e, args);
    }

}

function poolHasToken(address token) {
    require pool.token0() == token || pool.token1() == token || pool.token2() == token;
}
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
// using ConstantProductPool as pool
using SymbolicPool as pool

////////////////////////////////////////////////////////////////////////////
//                                Methods                                 //
////////////////////////////////////////////////////////////////////////////
/*
    Declaration of methods that are used in the rules. envfree indicate that
    the method is not dependent on the environment (msg.value, msg.sender).
    Methods that are not declared here are assumed to be dependent on env.
*/
methods {
    // BentoBox
    bento.transfer(address token, address from, address to, uint256 shares)
    bento.deposit(address, address, address, uint256, uint256) returns (uint256 amountOut, uint256 shareOut) 
    bento.balanceOf(address token, address user) returns (uint256) envfree

    // for solidity calls 
    toAmount(address token, uint256 share, bool roundUp) returns (uint256) => DISPATCHER(true)
    toShare(address token, uint256 amount, bool roundUp) returns (uint256) => DISPATCHER(true)
    transfer(address token, address from, address to, uint256 shares) => DISPATCHER(true) 
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
    withdraw(uint256) => DISPATCHER(true)

    // IPool
    // TODO: IPool or SymbolicPool?
    swap(bytes) returns (uint256) => DISPATCHER(true)
    flashSwap(bytes) returns (uint256) => DISPATCHER(true)
    mint(bytes) returns (uint256) => DISPATCHER(true)
    burn(bytes) => DISPATCHER(true) // TODO: missing return value??
    burnSingle(bytes data) returns (uint256) => DISPATCHER(true)
    
    // Pool helper
    pool.balanceOf(address) returns (uint256) envfree 
    pool.token0() returns (address) envfree
    pool.token1() returns (address) envfree
    pool.reserve0() returns (uint256) envfree 
    pool.reserve1() returns (uint256) envfree 
    
    // receiver
    sendTo() => DISPATCHER(true)
    tokenBalanceOf(address, address) returns (uint256) envfree
}

////////////////////////////////////////////////////////////////////////////
//                                 Rules                                  //
////////////////////////////////////////////////////////////////////////////
/*
rule sanity(method f) {
    env e;

    calldataarg args;
    f(e,args);

    assert false;
}
*/

// TridentRouter shouldn't hold any balance in any token.
rule tridentRouterTokenBalanceShouldBeZero(method f) filtered { f -> !f.isView && !f.isFallback } {
    env e;
    calldataarg args;

    address tokenIn;
    address tokenOut; 
    address recipient;
    bool unwrapBento;
    uint256 amount; 
    uint256 min;

    // if tokenA can be anything its enough one. I think this rule breaks
    // on the issue that the trident router does not check that one use the
    // right token for the pool used
    setupPoolAndMsgSender(e.msg.sender, tokenIn);
    poolIsBalanced();
    require tokenA.balanceOf(e, currentContract) == 0;
    // require ethBalance(e, currentContract) == 0;
    require bento.balanceOf(tokenA, currentContract) == 0;

    require recipient != currentContract && recipient != pool;
    callFunction(e.msg.sender, f, tokenIn, tokenOut, pool, recipient, unwrapBento, amount, min);

    assert tokenA.balanceOf(e, currentContract) == 0;
    // assert ethBalance(e, currentContract) == 0;
    assert bento.balanceOf(tokenA, currentContract) == 0;
}

// TODO: passing too quickly, need to check
// TODO: passing with assert false (rule is vacuous)
rule inverseOfSwapping(address tokenIn, address tokenOut, uint256 amountIn) {
    env e;

    address user = e.msg.sender;
    address recipient;
    bool unwrapBento;
    uint256 deadline;
    uint256 amountOutMinimum;
    
    setupPoolAndMsgSender(user, tokenIn);
    require tokenIn == tokenA || tokenIn == tokenB || tokenIn == tokenWeth; // TODO: this one is unnecessary?

    // setting up tokenOut
    require tokenOut != tokenIn;
    require tokenOut == tokenA || tokenOut == tokenB || tokenOut == tokenWeth;

    // ratio 1:1
    require(pool.reserve0() == pool.reserve1());
    // pool is at a stable state 
    poolIsBalanced();
    
    // TODO: SymbolicPool has no fee, do we just want to check with fee? coverage?
    // TODO: what about other methods?
    uint256 amountInToOut = callExactInputSingle(e, tokenIn, pool, pool, unwrapBento, amountIn, amountOutMinimum);
    uint256 amountOutToIn = callExactInputSingle(e, tokenOut, pool, recipient, unwrapBento, amountInToOut, amountOutMinimum);
    uint256 epsilon = 1;

    assert amountIn - epsilon <= amountOutToIn && 
           amountOutToIn <= amountIn + epsilon;
}

rule integrityOfAddLiquidity(address token, uint256 x, uint256 amount) {
    env e;

    address zeroAddress = 0;
    uint256 zeroAmount = 0;
    uint256 minLiquidity;
    address user = e.msg.sender;
    bool isNative;
    
    setupPoolAndMsgSender(user,token);
    // pool is at a stable state 
    poolIsBalanced();
   
    require amount == x * 2; // just to avoid round by 1 

    uint256 nativeBalance = tokenBalanceOf(token, user);
    uint256 bentoBalance = bento.balanceOf(token, user);
    require (nativeBalance < max_uint64 && bentoBalance < max_uint64);
    mathint userTokenBalanceBefore = tokenBalanceOf(token, user) + bento.balanceOf(token, user);
    uint256 poolTokenBalanceBefore = bento.balanceOf(token, pool);
    uint256 userLiquidityBalanceBefore = pool.balanceOf(user);
    uint256 liquidity = callAddLiquidity(e, token, amount, isNative, zeroAddress, zeroAmount, isNative, pool, user, minLiquidity);
    
    mathint userTokenBalanceAfter = tokenBalanceOf(token, user) + bento.balanceOf(token, user);
    uint256 poolTokenBalanceAfter = bento.balanceOf(token, pool);
    uint256 userLiquidityBalanceAfter = pool.balanceOf(user);

    assert userTokenBalanceAfter == userTokenBalanceBefore - amount;
    assert poolTokenBalanceAfter == poolTokenBalanceBefore + amount;
    require userLiquidityBalanceBefore + liquidity <= max_uint256;
    assert userLiquidityBalanceAfter == userLiquidityBalanceBefore + liquidity;

    assert liquidity > 0 <=> amount > 0;
    assert liquidity >= minLiquidity;
}


rule inverseOfMintAndBurnSingle(address token, uint256 amount) {
    env e;

    uint256 minLiquidity;
    address user = e.msg.sender;
    address zeroAddress = 0;
    uint256 zeroAmount = 0;
    bool isNative = true;
    
    setupPoolAndMsgSender(user, token);
    
    // pool is at a stable state 
    poolHasToken(token);
    poolIsBalanced();

    uint256 userTokenBalanceBefore = tokenBalanceOf(token, e.msg.sender);

    uint256 liquidity = callAddLiquidity(e, token, amount, isNative, zeroAddress, zeroAmount, isNative, pool, e.msg.sender, minLiquidity);
    callBurnLiquiditySingle(e, pool, liquidity, token, e.msg.sender, true, 0);

    uint256 userTokenBalanceAfter = tokenBalanceOf(token, e.msg.sender);

    assert( userTokenBalanceAfter == userTokenBalanceBefore);
}

/*
rule inverseOfMintAndBurnDual(address token1, address token2, uint256 amount1, uint256 amount2) {
    env e;
    uint256 deadline;
    uint256 minLiquidity;
    address user = e.msg.sender;

    poolHasToken(token1);
    poolHasToken(token2);

    require token1 != pool && token2 != pool;
    require user != bento && user != pool && user != currentContract;
    // pool is at a stable state
    poolIsBalanced();

    uint256 userToken1BalanceBefore = tokenBalanceOf(token1, e.msg.sender);
    uint256 userToken2BalanceBefore = tokenBalanceOf(token2, e.msg.sender);
    uint256 liquidity = callAddLiquidityUnbalanced(e, token1, amount1, token2, amount2, pool, e.msg.sender, deadline, minLiquidity);
    callBurnLiquidity(e, pool, liquidity, token1, token2, e.msg.sender, false, deadline, );
    uint256 userToken1BalanceAfter = tokenBalanceOf(token1, e.msg.sender);
    uint256 userToken2BalanceAfter = tokenBalanceOf(token2, e.msg.sender);
    assert( userToken1BalanceAfter == userToken1BalanceBefore && userToken2BalanceAfter == userToken2BalanceBefore);

}
*/ 

rule noChangeToOther(method f, address token, address other) {
    env e;
    calldataarg args;

    address user = e.msg.sender;
    
    setupPoolAndMsgSender(user, token);

    require user != other && bento != other && other != pool && other != currentContract;

    uint256 native = tokenBalanceOf(token, other);
    uint256 inBento = bento.balanceOf(token, other);
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

    assert tokenBalanceOf(token, other) == native &&
           bento.balanceOf(token, other) == inBento &&
           ethBalance(e, other) == eth &&
           pool.balanceOf(other) == liquidity;
}

rule validityOfUnwrapBento(address token, method f) {
    address tokenIn; 
    address tokenOut; 
    address recipient;
    bool unwrapBento;
    uint256 amount; 
    uint256 min;
    address user; 
    
    setupPoolAndMsgSender(user, token);
    
    require unwrapBento == true;
    require recipient != currentContract;
    uint256 before = bento.balanceOf(token, user);
    callFunction(user, f, tokenIn, tokenOut, pool, recipient, unwrapBento, amount, min);

    assert bento.balanceOf(token, user) == before;
}

////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////
// TODO: missing some functions???
function callFunction(address msgSender, method f, address tokenIn, address tokenOut,
                      address _pool, address recipient, bool unwrapBento, uint256 amount,
                      uint256 min) {
    env e;
    require e.msg.sender == msgSender;
    
    if (f.selector == callExactInputSingle(address,address,address,bool,uint256,uint256).selector) {
        callExactInputSingle(e, tokenIn, _pool, recipient, unwrapBento, amount, min);
    } else if (f.selector == callExactInputSingleWithNativeToken(address,address,address,bool,uint256,uint256).selector) {
        callExactInputSingleWithNativeToken(e, tokenIn, _pool, recipient, unwrapBento, amount, min);
    } else if (f.selector == callAddLiquidity(address,uint256,bool,address,uint256,bool,address,address,uint256).selector) {
        address zeroAddress = 0;
        uint256 zeroAmount = 0;
    
        callAddLiquidity(e, tokenIn, amount, unwrapBento, zeroAddress, zeroAmount, unwrapBento, _pool, recipient, min);
    } else if (f.selector == callBurnLiquiditySingle(address,uint256,address,address,bool,uint256).selector) {
        callBurnLiquiditySingle(e, _pool, amount, tokenOut, recipient, unwrapBento, min);
    } else if (f.selector == sweepBentoBoxToken(address,uint256,address).selector) {
        sweepBentoBoxToken(e, tokenIn, amount, recipient);
    } else if (f.selector == sweepNativeToken(address,uint256,address).selector) {
        sweepNativeToken(e, tokenIn, amount, recipient);
    } else if (f.selector == refundETH().selector) {
        require e.msg.sender == recipient;
        refundETH(e);
    } else if (f.selector == unwrapWETH(uint256,address).selector) {
        unwrapWETH(e,amount,recipient);
    } else { 
        calldataarg args;
        f(e, args);
    }
}

function poolHasToken(address token) {
    require pool.token0() == token || pool.token1() == token;
}

function poolIsBalanced() {
    require pool.reserve0() == bento.balanceOf(pool.token0(), currentContract) &&
            pool.reserve1() == bento.balanceOf(pool.token1(), currentContract);
}

// TODO: Do we need to setup multiple pools (for the multihop methods)???
function setupPoolAndMsgSender(address sender, address token) {
    // pool's token0 can be either ERC20 or wETH
    require pool.token0() == tokenA || pool.token0() == tokenWeth;
    // pool's token1 can be either ERC20 or wETH
    require pool.token1() == tokenB || pool.token1() == tokenWeth;
    // pool's tokens can't be the same
    require pool.token0() != pool.token1();

    // token argument has to be one of the pool's tokens
    require token == pool.token0() || token == pool.token1();

    // limiting the caller for the TridentRouter functions
    require sender != bento && sender != pool && sender != currentContract;
}
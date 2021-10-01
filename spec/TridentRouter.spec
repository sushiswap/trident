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
    Declaration of methods that are used in the rules. envfree indicate that
    the method is not dependent on the environment (msg.value, msg.sender).
    Methods that are not declared here are assumed to be dependent on env.
*/
methods {
    // Trident state variables
    cachedMsgSender() returns (address) envfree
    cachedPool() returns (address) envfree

    // BentoBox
    bento.transfer(address token, address from, address to, uint256 shares)
    bento.deposit(address, address, address, uint256, uint256) returns (uint256 amountOut, uint256 shareOut) 
    bento.balanceOf(address token, address user) returns (uint256) envfree
    bento.toAmount(address token, uint256 share, bool roundUp) returns (uint256) envfree
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
    pool.rates(address, address) returns (uint256) envfree

    // receiver
    sendTo() => DISPATCHER(true)
    tokenBalanceOf(address, address) returns (uint256) envfree

    // MasterDeployer
    pools(address pool) returns bool => NONDET
}

////////////////////////////////////////////////////////////////////////////
//                               Invariants                               //
////////////////////////////////////////////////////////////////////////////
// cachedMsgSender is always 1, unless we are inside a callBack function
invariant integrityOfCached() 
    cachedMsgSender() == 1 && cachedPool() == 1

////////////////////////////////////////////////////////////////////////////
//                                 Rules                                  //
////////////////////////////////////////////////////////////////////////////
// TODO: New Rules:
// Testing eth wrapping
// Swap, malicious pool can steal input token. Shoudn't loose anything except input token.

// rule sanity(method f) {
//     env e;

//     calldataarg args;
//     f(e,args);

//     assert false;
// }

// Swapping tokenIn for tokenOut, followed by tokenOut for tokenIn should
// preserve msg.sender's balance and the final amountOut should be equal to
// the initial amountIn.
// TODO: Currently only testing callExactInputSingle, need to check others.
rule inverseOfSwapping() {
    env e;

    uint256 epsilon = 1;
    address tokenIn;
    address tokenOut;
    bool unwrapBento;
    uint256 amountIn;
    uint256 minimumAmountOut;
    bool roundUp;
    
    // Sushi says that it is safe to assume that the users pass the 
    // correct tokens i.e. the tokens they pass are the pool's tokens
    poolHasToken(tokenIn);
    poolHasToken(tokenOut);
    require tokenIn != tokenOut; // setupPool is not able to enforce this, maybe simplify later
    setupPool();
    setupMsgSender(e.msg.sender);
    // ratio 1:1
    require(pool.reserve0() == pool.reserve1()); // TODO: for simplifying? (why was Nurit doing this?) (timing out without this)
    // pool is at a stable state 
    poolIsBalanced();

    // for rates[tokenIn][tokenOut] = x <=> rates[tokenOut][tokenIn] = 1 / x
    require(pool.rates(tokenIn, tokenOut) == 1 && pool.rates(tokenOut, tokenIn) == 1);

    mathint _totalUserTokenIn = bento.toAmount(tokenIn, bento.balanceOf(tokenIn, e.msg.sender), roundUp) + 
                                tokenBalanceOf(tokenIn, e.msg.sender);
    mathint _totalUserTokenOut = bento.toAmount(tokenOut, bento.balanceOf(tokenOut, e.msg.sender), roundUp) + 
                                 tokenBalanceOf(tokenOut, e.msg.sender);

    // TODO: I think that to = msg.sender makes sense, so that we
    // can also check the actual balances of the msg.sender, but check with
    // Nurit. Earlier for the first call it was pool and the second call it
    // was a generic to, which didn't make sense to me.
    uint256 amountInToOut = callExactInputSingle(e, tokenIn, pool, e.msg.sender, unwrapBento, amountIn, minimumAmountOut);
    uint256 amountOutToIn = callExactInputSingle(e, tokenOut, pool, e.msg.sender, unwrapBento, amountInToOut, minimumAmountOut);

    mathint totalUserTokenIn_ = bento.toAmount(tokenIn, bento.balanceOf(tokenIn, e.msg.sender), roundUp) +
                                tokenBalanceOf(tokenIn, e.msg.sender);
    mathint totalUserTokenOut_ = bento.toAmount(tokenOut, bento.balanceOf(tokenOut, e.msg.sender), roundUp) + 
                                 tokenBalanceOf(tokenOut, e.msg.sender);

    assert(amountIn - epsilon <= amountOutToIn &&
           amountOutToIn <= amountIn + epsilon, "amountOutToIn incorrect");
    assert(_totalUserTokenIn == totalUserTokenIn_, "msg.sender's tokenIn balance not preserved");
    assert(_totalUserTokenOut == totalUserTokenOut_, "msg.sender's tokenOut balance not preserved");
}

// Assets are preserved before and after addLiquidity
// TODO: naming min -> minLiquidity produces compliation errors (not sure why, need to check)
// Seems like if most of the argument names are the same it errors
// Tried min -> minLiquidity but changed native2 -> native2temp, and no errors
rule integrityOfAddLiquidity(uint256 x, uint256 y) {
    env e;

    address user = e.msg.sender;
    address tokenIn1;
    uint256 amount1;
    bool native1;
    address tokenIn2;
    uint256 amount2;
    bool native2;
    uint256 min;
    bool roundUp;
    
    // Sushi says that it is safe to assume that the users pass the 
    // correct tokens i.e. the tokens they pass are the pool's tokens
    poolHasToken(tokenIn1);
    poolHasToken(tokenIn2);
    require tokenIn1 != tokenIn2; // setupPool is not able to enforce this, maybe simplify later
    setupPool();
    setupMsgSender(user);
    // pool is at a stable state 
    poolIsBalanced();
   
    // to avoid round by 1 TODO: not needed (passing without this, Nurit had it)
    // require amount1 == x * 2; 
    // require amount2 == y * 2;

    // TODO: failing when either of the token is tokenWeth and native is true.
    require tokenIn1 != tokenWeth;
    require tokenIn2 != tokenWeth;

    uint256 _userToken1Balance = tokenBalanceOf(tokenIn1, user);
    uint256 _userToken2Balance = tokenBalanceOf(tokenIn2, user);
    uint256 _userToken1BentoBalance = bento.balanceOf(tokenIn1, user);
    uint256 _userToken2BentoBalance = bento.balanceOf(tokenIn2, user);
    uint256 _userLiquidityBalance = pool.balanceOf(user);

    uint256 _poolToken1Balance = bento.balanceOf(tokenIn1, pool);
    uint256 _poolToken2Balance = bento.balanceOf(tokenIn2, pool);

    uint256 liquidity = callAddLiquidity(e, tokenIn1, amount1, native1, tokenIn2, amount2, native2, pool, user, min);

    uint256 userToken1Balance_ = tokenBalanceOf(tokenIn1, user);
    uint256 userToken2Balance_ = tokenBalanceOf(tokenIn2, user);
    uint256 userToken1BentoBalance_ = bento.balanceOf(tokenIn1, user);
    uint256 userToken2BentoBalance_ = bento.balanceOf(tokenIn2, user);
    uint256 userLiquidityBalance_ = pool.balanceOf(user);

    uint256 poolToken1Balance_ = bento.balanceOf(tokenIn1, pool);
    uint256 poolToken2Balance_ = bento.balanceOf(tokenIn2, pool);

    if (!native1) {
        assert(userToken1BentoBalance_ == _userToken1BentoBalance - amount1, "user token1 bento balance");
    } else {
        // TODO: need to check roundUp (passing in both, check carefully)
        assert(userToken1Balance_ == _userToken1Balance - bento.toAmount(tokenIn1, amount1, roundUp), "user token1 balance");
    }

    if (!native2) {
        assert(userToken2BentoBalance_ == _userToken2BentoBalance - amount2, "user token2 bento balance");
    } else {
        // TODO: need to check roundUp (passing in both, check carefully)
        assert(userToken2Balance_ == _userToken2Balance - bento.toAmount(tokenIn2, amount2, roundUp), "user token2 balance");
    }
    
    assert(poolToken1Balance_ == _poolToken1Balance + amount1, "pool token1 balance");
    assert(poolToken2Balance_ == _poolToken2Balance + amount2, "pool token2 balance");

    // to prevent overflow
    require _userLiquidityBalance + liquidity <= max_uint256;
    assert(userLiquidityBalance_ == _userLiquidityBalance + liquidity, "userLiquidityBalance");

    assert(liquidity > 0 <=> (amount1 > 0 || amount2 > 0), "liquidity amount implication");
    assert(liquidity >= min, "liquidity less than minLiquidity");
}

// TODO: naming min -> minLiquidity produces compliation errors (not sure why, need to check)
// Seems like if most of the argument names are the same it errors
// Tried min -> minLiquidity but changed native2 -> native2temp, and no errors
rule inverseOfMintAndBurn(address token, uint256 amount) {
    env e;

    // TODO: temp require, to prevent the transfer of Eth
    // require e.msg.value == 0;

    address user = e.msg.sender;
    address tokenIn1;
    uint256 amount1;
    bool native1;
    address tokenIn2;
    uint256 amount2;
    bool native2;
    uint256 min;
    bool unwrapBento;
    uint256 minToken1;
    uint256 minToken2;
    bool roundUp;
    uint256 epsilon = 1;

    // Sushi says that it is safe to assume that the users pass the 
    // correct tokens i.e. the tokens they pass are the pool's tokens
    poolHasToken(tokenIn1);
    poolHasToken(tokenIn2);
    require tokenIn1 != tokenIn2; // setupPool is not able to enforce this, maybe simplify later
    setupPool();
    setupMsgSender(user);
    // pool is at a stable state 
    poolIsBalanced();
    // TODO: check that this is safe
    require pool.balanceOf(pool) == 0;

    // since on burning symbolic pool returns 1/2 of liquidity for each token
    require amount1 == amount2;
    
    mathint _userToken1Balance = tokenBalanceOf(tokenIn1, user) + bento.toAmount(tokenIn1, bento.balanceOf(tokenIn1, user), roundUp);
    mathint _userToken2Balance = tokenBalanceOf(tokenIn2, user) + bento.toAmount(tokenIn2, bento.balanceOf(tokenIn2, user), roundUp);

    uint256 liquidity = callAddLiquidity(e, tokenIn1, amount1, native1, tokenIn2, amount2, native2, pool, user, min);
    // require liquidity > 1; // TODO: temp (if liquidity < 2, burning would result in 0)

    // TODO: check to = user, minToken1 and minToken2 doesn't result in vacuous rule
    callBurnLiquidity(e, pool, liquidity, user, unwrapBento, tokenIn1, tokenIn2, minToken1, minToken2);

    mathint userToken1Balance_ = tokenBalanceOf(tokenIn1, user) + bento.toAmount(tokenIn1, bento.balanceOf(tokenIn1, user), roundUp);
    mathint userToken2Balance_ = tokenBalanceOf(tokenIn2, user) + bento.toAmount(tokenIn2, bento.balanceOf(tokenIn2, user), roundUp);

    // TODO: might want to also check user's pool token balance
    // These make no sense since user can transfer x tokenA and y tokenB,
    // they will receive z = x + y liquidity (based on our SymbolicPool implementation).
    // Then when they burn, they will receive z / 2 for each token not x and y respectively.
    // assert(_userToken1Balance == userToken1Balance_);
    // assert(_userToken2Balance == userToken2Balance_);

    assert(_userToken1Balance - epsilon <= userToken1Balance_ &&
           userToken1Balance_ <= _userToken1Balance + epsilon, "userToken1Balance_ incorrect");
    assert(_userToken2Balance - epsilon <= userToken2Balance_ &&
           userToken2Balance_ <= _userToken2Balance + epsilon, "userToken2Balance_ incorrect");
}

// rule inverseOfMintAndBurnDual(address token1, address token2, uint256 amount1, uint256 amount2) {
//     env e;
//     uint256 deadline;
//     uint256 minLiquidity;
//     address user = e.msg.sender;

//     poolHasToken(token1);
//     poolHasToken(token2);

//     require token1 != pool && token2 != pool;
//     require user != bento && user != pool && user != currentContract;
//     // pool is at a stable state
//     poolIsBalanced();

//     uint256 userToken1BalanceBefore = tokenBalanceOf(token1, e.msg.sender);
//     uint256 userToken2BalanceBefore = tokenBalanceOf(token2, e.msg.sender);
//     uint256 liquidity = callAddLiquidityUnbalanced(e, token1, amount1, token2, amount2, pool, e.msg.sender, deadline, minLiquidity);
//     callBurnLiquidity(e, pool, liquidity, token1, token2, e.msg.sender, false, deadline, );
//     uint256 userToken1BalanceAfter = tokenBalanceOf(token1, e.msg.sender);
//     uint256 userToken2BalanceAfter = tokenBalanceOf(token2, e.msg.sender);
//     assert( userToken1BalanceAfter == userToken1BalanceBefore && userToken2BalanceAfter == userToken2BalanceBefore);
// }

rule noChangeToOther() {
    method f;
    env e;

    address other;
    address user = e.msg.sender;
    address token;
    uint256 amount;
    address to;
    bool unwrapBento;
    bool native1;
    bool native2;
    
    poolHasToken(token);
    setupPool();
    setupMsgSender(user);

    require user != other && bento != other && other != pool && other != currentContract;
    require to != other; // TODO: if to == other, then balances can increase?

    // TODO: HERE IT IS FINE (dangerous because setupMsgSender requires
    // msg.sender == user, and some methods do cachedMsgSender = msg.sender, 
    // but here we say cachedMsgSender != user (msg.sender))
    require cachedMsgSender() != other;

    uint256 _native = tokenBalanceOf(token, other);
    uint256 _inBento = bento.balanceOf(token, other);
    uint256 _eth = ethBalance(e, other);
    uint256 _liquidity = pool.balanceOf(other);

    callFunction(f, e.msg.sender, token, amount, pool, to, unwrapBento, native1, native2);

    uint256 native_ = tokenBalanceOf(token, other);
    uint256 inBento_ = bento.balanceOf(token, other);
    uint256 eth_ = ethBalance(e, other);
    uint256 liquidity_ = pool.balanceOf(other);

    assert(_native == native_, "native changed");
    assert(_inBento == inBento_, "inBento changed");
    assert(_eth == eth_, "eth changed");
    // TODO: when mint is called 'to' might be other due to which other's liquidity
    // increases (passes on addLiquidityLazy with <=), running with unchecked commented
    // out in TridentERC20
    assert(_liquidity <= liquidity_, "liquidity changed");
}

// Testing only on native functions (money comes from ERC20 or Eth
// instead of BentoBox transfer) and unwrapBento = true
// users BentoBox balances shouldn't change
rule validityOfUnwrapBento(method f) filtered { f -> 
        f.selector != callExactInputSingle(address, address, address, bool, uint256, uint256).selector &&
        f.selector != callExactInput(address, address, address, address, address, bool, uint256, uint256).selector &&
        f.selector != certorafallback_0().selector } {
    address user; 
    address token;
    uint256 amount;
    address to;
    bool unwrapBento;
    bool native1;
    bool native2;
    
    poolHasToken(token);
    setupPool();
    setupMsgSender(user);
    
    require to != currentContract;
    require unwrapBento == true;
    require native1 == true && native2 == true;

    uint256 before = bento.balanceOf(token, user);

    callFunction(f, user, token, amount, pool, to, unwrapBento, native1, native2);

    uint256 after = bento.balanceOf(token, user);

    // for the callbacks pay close attention to the setupMsgSender and the
    // callback code. setupMsgSender -> user != pool, and callback ->
    // msg.sender == cachedPool. But for now it is fine since when we say
    // pool we are refering to the SymbolicPool and the tool is able to
    // assign an address != SymbolicPool to cachedPool.
    if (f.selector == tridentSwapCallback(bytes).selector || 
        f.selector == tridentMintCallback(bytes).selector) {
        require cachedMsgSender() != user;

        assert(after >= before, "user's BentoBox balance changed");
    } else if (f.selector == sweepBentoBoxToken(address, uint256, address).selector && user == to) {
        // sweeping BentoBox will increase the user's balance
        assert(after == before + amount, "user didn't sweep BentoBox");
    } else {
        assert(after == before, "user's BentoBox balance changed");
    }
}

////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////
function setupMsgSender(address sender) {
    require sender != bento && sender != pool && sender != currentContract;
}

function setupPool() {
    // pool's token0 can be either ERC20 or wETH
    require pool.token0() == tokenA || pool.token0() == tokenWeth;
    // pool's token1 can be either ERC20 or wETH
    require pool.token1() == tokenB || pool.token1() == tokenWeth;
    // pool's tokens can't be the same
    require pool.token0() != pool.token1();
}

function poolHasToken(address token) {
    require pool.token0() == token || pool.token1() == token;
}

function poolIsBalanced() {
    require pool.reserve0() == bento.balanceOf(pool.token0(), pool) &&
            pool.reserve1() == bento.balanceOf(pool.token1(), pool);
}

// TODO: missing functions:
//     callExactInput
//     callExactInputLazy
//     callExactInputWithNativeToken
//     complexPath
//     callBurnLiquidity
//     seems like we are currently only limiting the params of single pool
//     functions. So violations on the above methods are expected.
// discuss how do you want to handle multipool calls?
// the callFunction arguments list would become huge
function callFunction(method f, address user, address token, uint256 amount,
                      address _pool, address to, bool unwrapBento, bool native1, bool native2) {
    env e;
    require user == e.msg.sender;

    uint256 minimumAmountOut;
    uint256 liquidity;
    address tokenIn1;
    address tokenIn2;
    
    if (f.selector == callExactInputSingle(address, address, address, bool, uint256, uint256).selector) {
        callExactInputSingle(e, token, _pool, to, unwrapBento, amount, minimumAmountOut);
    } else if (f.selector == callExactInputSingleWithNativeToken(address, address, address, bool, uint256, uint256).selector) {
        callExactInputSingleWithNativeToken(e, token, _pool, to, unwrapBento, amount, minimumAmountOut);
    } else if (f.selector == callAddLiquidity(address, uint256, bool, address, uint256, bool, address, address, uint256).selector) {
        uint256 amount1;
        uint256 amount2;
        uint256 minPoolTokenLiquidity;

        callAddLiquidity(e, tokenIn1, amount1, native1, tokenIn2, amount2, native2, _pool, to, minPoolTokenLiquidity);
    } else if (f.selector == callBurnLiquidity(address, uint256, address, bool, address, address, uint256, uint256).selector) {
        uint256 minToken1;
        uint256 minToken2;

        callBurnLiquidity(e, _pool, liquidity, to, unwrapBento, tokenIn1, tokenIn2, minToken1, minToken2);
    } else if (f.selector == callBurnLiquiditySingle(address, uint256, address, address, bool, uint256).selector) {
        callBurnLiquiditySingle(e, _pool, liquidity, token, to, unwrapBento, minimumAmountOut);
    } else if (f.selector == sweepBentoBoxToken(address, uint256, address).selector) {
        sweepBentoBoxToken(e, token, amount, to);
    } else if (f.selector == sweepNativeToken(address, uint256, address).selector) {
        sweepNativeToken(e, token, amount, to);
    } else if (f.selector == refundETH().selector) {
        require to == e.msg.sender;
        refundETH(e);
    } else if (f.selector == unwrapWETH(uint256, address).selector) {
        unwrapWETH(e, amount, to);
    } else { 
        calldataarg args;
        f(e, args);
    }
}
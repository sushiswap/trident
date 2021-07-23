/*
    This is a specification file for the verification of ConstantProductPool.sol
    smart contract using the Certora prover. For more information,
	visit: https://www.certora.com/

    This file is run with scripts/verifyConstantProductPool.sol
	Assumptions:
*/

using SimpleBentoBox as bentoBox

////////////////////////////////////////////////////////////////////////////
//                                Methods                                 //
////////////////////////////////////////////////////////////////////////////
/*
    Declaration of methods that are used in the rules. envfree indicate that
    the method is not dependent on the environment (msg.value, msg.sender).
    Methods that are not declared here are assumed to be dependent on env.
*/

methods {
    // ConstantProductPool state variables
    token0() returns (address) envfree
    token1() returns (address) envfree
    reserve0() returns (uint128) envfree
    reserve1() returns (uint128) envfree

    // ConstantProductPool functions
    _balance() returns (uint256 balance0, uint256 balance1) envfree
    transferFrom(address, address, uint256) envfree

    // MirinERC20 (permit)
    ecrecover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) 
              returns (address) => NONDET

    // ConstantProductPool (swap, swapWithContext) -> IMirinCallee (mirinCall)
    mirinCall(address sender, uint256 amount0Out, uint256 amount1Out, bytes data) => NONDET

    // simplification of sqrt
    sqrt(uint256 x) returns (uint256) => DISPATCHER(true) UNRESOLVED

    // bentobox
    bentoBox.balanceOf(address token, address user) returns (uint256) envfree
    bentoBox.transfer(address token, address from, address to, uint256 share) envfree

    // IERC20
    tokenBalanceOf(address token, address user) returns (uint256 balance) envfree 
}

////////////////////////////////////////////////////////////////////////////
//                                 Ghost                                  //
////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////
//                               Invariants                               //
////////////////////////////////////////////////////////////////////////////
invariant reserveLessThanEqualToBalance()
    reserve0() <= bentoBox.balanceOf(token0(), currentContract) && 
    reserve1() <= bentoBox.balanceOf(token1(), currentContract)
    
////////////////////////////////////////////////////////////////////////////
//                                 Rules                                  //
////////////////////////////////////////////////////////////////////////////
// rule sanity(method f) {
//     env e;
//     calldataarg args;
//     f(e, args);

//     assert(false);
// }

rule noChangeToBalancedPoolAssets(method f) {
    env e;

    uint256 _balance0;
    uint256 _balance1;

    _balance0, _balance1 = _balance();

    require reserve0() == _balance0 && reserve1() == _balance1;

    calldataarg args;
    f(e, args);

    uint256 balance0_;
    uint256 balance1_;

    balance0_, balance1_ = _balance();

    assert(_balance0 == balance0_ && _balance1 == balance1_, 
           "pool's balance in BentoBox changed");
}

rule afterOpBalanceEqualsReserve(method f) {
    env e;

    uint256 _balance0;
    uint256 _balance1;

    _balance0, _balance1 = _balance();

    requireInvariant reserveLessThanEqualToBalance();

    calldataarg args;
    f(e, args);

    uint256 balance0_;
    uint256 balance1_;

    balance0_, balance1_ = _balance();

    // reserve can go up or down or the balance doesn't change
    assert(reserve0() == balance0_ && reserve1() == balance1_,
           "balance doesn't equal reserve after operations");
}

rule mintingNotPossibleForBalancedPool() {
    env e;

    uint256 balance0;
    uint256 balance1;

    balance0, balance1 = _balance();

    require reserve0() == balance0 && reserve1() == balance1;

    calldataarg args;
    uint256 liquidity = mint(e, args);

    assert(lastReverted || liquidity == 0, 
           "pool minting on no transfer to pool");
}

// TODO: only when adding optimal liquidity
rule inverseOfMintAndBurn() {
    env e;

    uint256 balance0;
    uint256 balance1;

    balance0, balance1 = _balance();

    require reserve0() < balance0 && reserve1() < balance1;

    // asumming addLiquidity is already called and the assets are transfered
    // to the pool
    uint256 _liquidity0 = balance0 - reserve0();
    uint256 _liquidity1 = balance1 - reserve1();

    calldataarg args0;
    uint256 mirinLiquidity = mint(e, args0);

    // transfer mirin tokens to the pool
    transferFrom(e.msg.sender, currentContract, mirinLiquidity);

    uint256 liquidity0_;
    uint256 liquidity1_;

    calldataarg args1;
    liquidity0_, liquidity1_ = burnGetter(e, args1);

    // do we instead want to check whether the 'to' user got the funds? (Ask Nurit) -- Yes
    assert(_liquidity0 == liquidity0_ && _liquidity1 == liquidity1_, 
           "inverse of mint then burn doesn't hold");
}

rule burnTokenAdditivity() {
    env e;
    address to;
    bool unwrapBento;
    uint256 mirinLiquidity;

    uint256 balance0;
    uint256 balance1;

    balance0, balance1 = _balance();

    require reserve0() == balance0 && reserve1() == balance1;

    // need to replicate the exact state later on
    storage initState = lastStorage;

    // burn single token
    transferFrom(e.msg.sender, currentContract, mirinLiquidity);
    uint256 liquidity0Single = burnLiquiditySingle(e, token0(), to, unwrapBento);

    uint256 _totalUsertoken0 = tokenBalanceOf(token0(), e.msg.sender) + 
                               bentoBox.balanceOf(token0(), e.msg.sender);
    uint256 _totalUsertoken1 = tokenBalanceOf(token1(), e.msg.sender) + 
                               bentoBox.balanceOf(token1(), e.msg.sender);

    uint256 liquidity0;
    uint256 liquidity1;

    // burn both tokens
    transferFrom(e.msg.sender, currentContract, mirinLiquidity) at lastStorage;
    liquidity0, liquidity1 = burnGetter(e, to, unwrapBento);

    // swap token1 for token0
    // Don't know what's wrong with this (Ask Nurit)
    // bentoBox.transfer(token1(), e.msg.sender, currentContract, liquidity1);
    uint256 amountOut = swapWithoutContext(e, token1(), token0(), to, unwrapBento);

    uint256 totalUsertoken0_ = tokenBalanceOf(token0(), e.msg.sender) + 
                               bentoBox.balanceOf(token0(), e.msg.sender);
    uint256 totalUsertoken1_ = tokenBalanceOf(token1(), e.msg.sender) + 
                               bentoBox.balanceOf(token1(), e.msg.sender);

    assert(liquidity0Single == liquidity0 + amountOut, "burns not equivalent");
    assert(_totalUsertoken0 == totalUsertoken0_, "user's token0 changed");
    assert(_totalUsertoken1 == totalUsertoken1_, "user's token1 changed");
}

////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////
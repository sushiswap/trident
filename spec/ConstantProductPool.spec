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
    // state variables
    token0() returns (address) envfree
    token1() returns (address) envfree

    reserve0() returns (uint128) envfree
    reserve1() returns (uint128) envfree

    // ConstantProductPool functions
    _balance() returns (uint256 balance0, uint256 balance1) envfree

    // MirinERC20 (permit)
    ecrecover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) 
              returns (address) => NONDET

    // ConstantProductPool (swap, swapWithContext) -> IMirinCallee (mirinCall)
    mirinCall(address sender, uint256 amount0Out, uint256 amount1Out, bytes data) => NONDET

    // simplification of sqrt
    sqrt(uint256 x) returns (uint256) => DISPATCHER(true) UNRESOLVED

    // bentobox
    bentoBox.balanceOf(address token, address user) returns (uint256) envfree
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

    // no need? (Ask Nurit)
    require reserve0() <= _balance0 && reserve1() <= _balance1;

    calldataarg args;
    f(e, args);

    uint256 balance0_;
    uint256 balance1_;

    balance0_, balance1_ = _balance();

    // reserve should go up. Does it make sense to use before
    // balance to compare here? (Ask Nurit)
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

rule inverseOfMintAndBurn() {
    env e;

    // do we actually want to add liquidity? (Ask Nurit)
    uint256 balance0;
    uint256 balance1;

    balance0, balance1 = _balance();

    require reserve0() < balance0 && reserve1() < balance1;

    uint256 _liquidity0 = balance0 - reserve0();
    uint256 _liquidity1 = balance1 - reserve1();

    calldataarg args0;
    uint256 liquidity = mint(e, args0);

    uint256 liquidity0_;
    uint256 liquidity1_;

    calldataarg args1;
    liquidity0_, liquidity1_ = burnGetter(e, args1);

    // do we instead want to check whether the 'to' user got the funds? (Ask Nurit)
    assert(_liquidity0 == liquidity0_ && _liquidity1 == liquidity1_, 
           "inverse of mint then burn doesn't hold");
}

////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////
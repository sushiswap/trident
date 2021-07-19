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

    reserve0() returns (uint112) envfree
    reserve1() returns (uint112) envfree

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
    reserve0() <= bentoBox.balanceOf(token0(), currentContract) && reserve1() <= bentoBox.balanceOf(token1(), currentContract)
    
///////////////////////// ///////////////////////////////////////////////////
//                                 Rules                                  //
////////////////////////////////////////////////////////////////////////////
// rule sanity(method f) {
//     env e;
//     calldataarg args;
//     f(e, args);

//     assert(false);
// }

////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////
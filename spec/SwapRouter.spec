/*
    This is a specification file for smart contract verification
    with the Certora prover. For more information,
	visit: https://www.certora.com/

    This file is run with scripts/...
	Assumptions:
*/

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
}

rule exactInputSingleCanBeHarnessed() {
    env e;

    calldataarg args;

    exactInputSingle(e, args);

    assert true;
}
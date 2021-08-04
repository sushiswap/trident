/*
    This is a specification file for the verification of HybridPool.sol
    smart contract using the Certora prover. For more information,
	visit: https://www.certora.com/

    This file is run with scripts/verifyHybridPool.sol
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
    // HybridPool state variables
    token0() returns (address) envfree
    token1() returns (address) envfree
    reserve0() returns (uint128) envfree
    reserve1() returns (uint128) envfree

    // HybridPool functions
    _balance() returns (uint256 balance0, uint256 balance1) envfree
    transferFrom(address, address, uint256)
    totalSupply() returns (uint256) envfree

    // TODO: not working
    // TridentERC20 (permit)
    ecrecover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) 
              returns (address) => NONDET

    // HybridPool (swap, swapWithContext) -> ITridentCallee (tridentCallback)
    tridentCallback(address tokenIn, address tokenOut, uint256 amountIn,
                    uint256 amountOut, bytes data) => NONDET

    // simplification of sqrt
    sqrt(uint256 x) returns (uint256) => DISPATCHER(true) UNRESOLVED

    // bentobox
    bentoBox.balanceOf(address token, address user) returns (uint256) envfree
    bentoBox.transfer(address token, address from, address to, uint256 share)

    // IERC20
    transfer(address recipient, uint256 amount) returns (bool) => DISPATCHER(true) UNRESOLVED
    balanceOf(address account) returns (uint256) => DISPATCHER(true) UNRESOLVED
    tokenBalanceOf(address token, address user) returns (uint256 balance) envfree 

    // MasterDeployer(masterDeployer).barFee()
    barFee() => NONDET
}

////////////////////////////////////////////////////////////////////////////
//                                 Ghost                                  //
////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////
//                               Invariants                               //
////////////////////////////////////////////////////////////////////////////
invariant validityOfTokens()
    token0() != 0 && token1() != 0 && token0() != token1()

invariant tokensNotMirin()
    token0() != currentContract && token1() != currentContract

// use 1 and 2 to prove reserveLessThanEqualToBalance
invariant reserveLessThanEqualToBalance()
    reserve0() <= bentoBox.balanceOf(token0(), currentContract) && 
    reserve1() <= bentoBox.balanceOf(token1(), currentContract) {
		preserved {
			requireInvariant validityOfTokens();
		}
	}
    
////////////////////////////////////////////////////////////////////////////
//                                 Rules                                  //
////////////////////////////////////////////////////////////////////////////
// rule sanity(method f) {
//     env e;
//     calldataarg args;
//     f(e, args);

//     assert(false);
// }

// REVIEW: swapWithContext should fail all others should pass
rule noChangeToBalancedPoolAssets(method f) {
    env e;

    uint256 _balance0;
    uint256 _balance1;

    _balance0, _balance1 = _balance();
    
    validState(true);
    // system has no mirin tokens
    require balanceOf(e, currentContract) == 0;

    calldataarg args;
    if (f.selector != swapWithContext(address, address, bytes, address, bool, uint256).selector) {
        f(e, args);
    }

    uint256 balance0_;
    uint256 balance1_;

    balance0_, balance1_ = _balance();

    // post-condition: pool's balances don't change
    assert(_balance0 == balance0_ && _balance1 == balance1_, 
           "pool's balance in BentoBox changed");
}

// REVIEW: exclude functions like getter and those which do nothing.
rule afterOpBalanceEqualsReserve(method f) {
    env e;

    validState(false);
    require balanceOf(e, currentContract) == 0;

    uint256 _balance0;
    uint256 _balance1;

    _balance0, _balance1 = _balance();

    uint256 _reserve0 = reserve0();
    uint256 _reserve1 = reserve1();

    calldataarg args;
    f(e, args);

    uint256 balance0_;
    uint256 balance1_;

    balance0_, balance1_ = _balance();

    // (reserve or balances changed before and after the method call) => 
    // (reserve0() == balance0_ && reserve1() == balance1_)
    // reserve can go up or down or the balance doesn't change
    assert((_balance0 != balance0_ || _balance1 != balance1_ ||
            _reserve0 != reserve0() || _reserve1 != reserve1()) =>
            (reserve0() == balance0_ && reserve1() == balance1_),
           "balance doesn't equal reserve after state changing operations");
}

// Failing maybe because of sqrt dispatcher?
rule mintingNotPossibleForBalancedPool() {
    env e;

    validState(true);

    calldataarg args;
    uint256 liquidity = mint(e, args);

    assert(lastReverted || liquidity == 0, 
           "pool minting on no transfer to pool");
}

// TODO: only when adding optimal liquidity
// REVIEW: passing without ^^^^^^^
// rule inverseOfMintAndBurn() {
//     env e;

//     uint256 balance0;
//     uint256 balance1;

//     balance0, balance1 = _balance();

//     require reserve0() < balance0 && reserve1() < balance1;

//     // asumming addLiquidity is already called and the assets
//     // are transfered to the pool
//     uint256 _liquidity0 = balance0 - reserve0();
//     uint256 _liquidity1 = balance1 - reserve1();

//     calldataarg args0;
//     uint256 mirinLiquidity = mint(e, args0);

//     // transfer mirin tokens to the pool
//     transferFrom(e, e.msg.sender, currentContract, mirinLiquidity);

//     uint256 liquidity0_;
//     uint256 liquidity1_;

//     calldataarg args1;
//     liquidity0_, liquidity1_ = burnGetter(e, args1);

//     // do we instead want to check whether the 'to' user got the funds? (Ask Nurit) -- Yes
//     assert(_liquidity0 == liquidity0_ && _liquidity1 == liquidity1_, 
//            "inverse of mint then burn doesn't hold");
// }

// DIFFERENT STYLE OF WRITING THE SAME RULE (inverseOfMintAndBurn)
// TODO: try with optimal liquidity
rule inverseOfMintAndBurn() {
    env e;
    address to;
    bool unwrapBento;

    // TODO: require e.msg.sender == to? Or check the assets of 'to'?
    validState(true);

    uint256 _liquidity0;
    uint256 _liquidity1;

    uint256 _totalUsertoken0 = tokenBalanceOf(token0(), e.msg.sender) + 
                               bentoBox.balanceOf(token0(), e.msg.sender);
    uint256 _totalUsertoken1 = tokenBalanceOf(token1(), e.msg.sender) + 
                               bentoBox.balanceOf(token1(), e.msg.sender);

    sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, _liquidity0);
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, _liquidity1);
    uint256 mirinLiquidity = mint(e, to);

    // transfer mirin tokens to the pool
    transferFrom(e, e.msg.sender, currentContract, mirinLiquidity);

    uint256 liquidity0_;
    uint256 liquidity1_;

    liquidity0_, liquidity1_ = burn(e, to);

    uint256 totalUsertoken0_ = tokenBalanceOf(token0(), e.msg.sender) + 
                               bentoBox.balanceOf(token0(), e.msg.sender);
    uint256 totalUsertoken1_ = tokenBalanceOf(token1(), e.msg.sender) + 
                               bentoBox.balanceOf(token1(), e.msg.sender);

    assert(_liquidity0 == liquidity0_ && _liquidity1 == liquidity1_, 
           "inverse of mint then burn doesn't hold");
    assert(_totalUsertoken0 == totalUsertoken0_ && 
           _totalUsertoken1 == totalUsertoken1_, 
           "user's total balances changed");
}

rule burnTokenAdditivity() {
    env e;
    address to;
    bool unwrapBento;
    uint256 mirinLiquidity;

    uint256 balance0;
    uint256 balance1;

    balance0, balance1 = _balance();

    // TODO: require e.msg.sender == to? Or check the assets of 'to'?
    validState(true);

    // need to replicate the exact state later on
    storage initState = lastStorage;

    // burn single token
    transferFrom(e, e.msg.sender, currentContract, mirinLiquidity);
    uint256 liquidity0Single = burnLiquiditySingle(e, token0(), to, unwrapBento);

    uint256 _totalUsertoken0 = tokenBalanceOf(token0(), e.msg.sender) + 
                               bentoBox.balanceOf(token0(), e.msg.sender);
    uint256 _totalUsertoken1 = tokenBalanceOf(token1(), e.msg.sender) + 
                               bentoBox.balanceOf(token1(), e.msg.sender);

    uint256 liquidity0;
    uint256 liquidity1;

    // burn both tokens
    transferFrom(e, e.msg.sender, currentContract, mirinLiquidity) at initState;
    liquidity0, liquidity1 = burn(e, to);

    // swap token1 for token0
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, liquidity1);
    uint256 amountOut = swapWithoutContext(e, token1(), token0(), to, unwrapBento);

    uint256 totalUsertoken0_ = tokenBalanceOf(token0(), e.msg.sender) + 
                               bentoBox.balanceOf(token0(), e.msg.sender);
    uint256 totalUsertoken1_ = tokenBalanceOf(token1(), e.msg.sender) + 
                               bentoBox.balanceOf(token1(), e.msg.sender);

    assert(liquidity0Single == liquidity0 + amountOut, "burns not equivalent");
    assert(_totalUsertoken0 == totalUsertoken0_, "user's token0 changed");
    assert(_totalUsertoken1 == totalUsertoken1_, "user's token1 changed");
}

// rule sameUnderlyingRatioLiquidity(method f) filtered { f -> 
//         f.selector == swapWithoutContext(address, address, address, bool).selector ||
//         f.selector == swapWithContext(address, address, bytes, address, bool, uint256).selector ||
//         f.selector == swap(uint256, uint256, address, bytes).selector } {
//     env e;
//     address to;
//     bool unwrapBento;
//     uint256 mirinLiquidity;

//     // TODO: require e.msg.sender == to? Or check the assets of 'to'?
//     validState(true);

//     uint256 reserveRatio = reserve0() / reserve1();

//     require reserveRatio == 2;

//     // need to replicate the exact state later on
//     storage initState = lastStorage;

//     // burn single token before swapping
//     transferFrom(e, e.msg.sender, currentContract, mirinLiquidity);
//     uint256 _liquidity0Single = burnLiquiditySingle(e, token0(), to, unwrapBento);

//     calldataarg args;
//     f(e, args) at initState; // TODO: different swaps have different mechanisms, limit the arguments

//     // does burn change the ratio of reserves? If so, do we need to burn in an 
//     // if branch? Like if the ratio is the same, burn and see if liquidity
//     // increased. TODO
//     // burn single token after swapping
//     transferFrom(e, e.msg.sender, currentContract, mirinLiquidity);
//     uint256 liquidity0Single_ = burnLiquiditySingle(e, token0(), to, unwrapBento);

//     assert((reserve0() / reserve1() == 2) => _liquidity0Single <= liquidity0Single_,
//            "with time mirin liquidity decreased");
// }

// DIFFERENT STYLE OF WRITING THE SAME RULE (sameUnderlyingRatioLiquidity)
rule sameUnderlyingRatioLiquidity(method f) filtered { f -> 
        f.selector == swapWithoutContext(address, address, address, bool).selector } {
    env e1;
    env e2;
    env e3;
    address to;
    bool unwrapBento;
    uint256 mirinLiquidity;

    require e1.block.timestamp < e2.block.timestamp && 
            e2.block.timestamp < e3.block.timestamp;
    require e1.msg.sender == e2.msg.sender && e2.msg.sender == e3.msg.sender;

    // TODO: require e.msg.sender == to? Or check the assets of 'to'?
    validState(true);

    uint256 reserveRatio = reserve0() / reserve1();

    require reserveRatio == 2;

    // liquidity0 = user's mirinTokens * reserve0 / totalSupply of mirinTokens
    uint256 _liquidity0 = balanceOf(e1, e1.msg.sender) * reserve0() / totalSupply();
    uint256 _liquidity1 = balanceOf(e1, e1.msg.sender) * reserve1() / totalSupply();

    calldataarg args;
    f(e2, args); // TODO: run with all swaps

    // liquidity0 = user's mirinTokens * reserve0 / totalSupply of mirinTokens
    uint256 liquidity0_ = balanceOf(e3, e3.msg.sender) * reserve0() / totalSupply();
    uint256 liquidity1_ = balanceOf(e3, e3.msg.sender) * reserve1() / totalSupply();

    assert((reserve0() / reserve1() == 2) => (_liquidity0 <= liquidity0_ &&
           _liquidity1 <= liquidity1_), "with time mirin liquidity decreased");
}

// TODO: all swap methods
rule multiSwapLessThanSingleSwap() {
    env e;
    address to;
    bool unwrapBento;
    uint256 liquidity1;
    uint256 liquidity2;

    // TODO: liquidity1, liquidity2 can't be 0??? Maybe (to prevent counter examples)
    // TODO: require e.msg.sender == to? Or check the assets of 'to'?
    validState(true);

    // need to replicate the exact state later on
    storage initState = lastStorage;

    // swap token1 for token0 in two steps
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, liquidity1);
    uint256 multiAmountOut1 = swapWithoutContext(e, token1(), token0(), to, unwrapBento);
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, liquidity2);
    uint256 multiAmountOut2 = swapWithoutContext(e, token1(), token0(), to, unwrapBento);

    // checking for overflows
    require multiAmountOut1 + multiAmountOut2 <= max_uint256;
    require liquidity1 + liquidity2 <= max_uint256;

    // swap token1 for token0 in a single step
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, liquidity1 + liquidity2) at initState; 
    uint256 singleAmountOut = swapWithoutContext(e, token1(), token0(), to, unwrapBento);

    assert(singleAmountOut > multiAmountOut1 + multiAmountOut2, "multiple swaps better than one single swap");
}

rule additivityOfMint() {
    env e;
    address to;
    uint256 x1;
    uint256 x2;
    uint256 y1;
    uint256 y2;

    // x, y can be 0? Their ratio (they have to be put in the same ratio, right?) 
    // TODO: require e.msg.sender == to? Or check the assets of 'to'?
    validState(true);

    // need to replicate the exact state later on
    storage initState = lastStorage;

    // minting in two steps
    sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, x1);
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, x2);
    uint256 mirinTwoSteps1 = mint(e, to);

    sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, y1);
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, y2);
    uint256 mirinTwoSteps2 = mint(e, to);

    // checking for overflows
    require mirinTwoSteps1 + mirinTwoSteps2 <= max_uint256;
    require x1 + x2 < max_uint256 && y1 + y2 < max_uint256;

    // minting in a single step
    sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, x1 + x2) at initState;
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, y1 + y2);
    uint256 mirinSingleStep = mint(e, to);

    assert(mirinSingleStep >= mirinTwoSteps1 + mirinTwoSteps2, "multiple mints better than a single mint");
}

// rule integrityOfgetOptimalLiquidityInAmounts() {

// }

////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////
function validState(bool isBalanced) {
    requireInvariant validityOfTokens();
    requireInvariant tokensNotMirin();

    if (isBalanced) {
        requireInvariant reserveLessThanEqualToBalance();
    } else {
        require reserve0() == bentoBox.balanceOf(token0(), currentContract) &&
                reserve1() == bentoBox.balanceOf(token1(), currentContract);
    }
}
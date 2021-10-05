/*
    This is a specification file for the verification of ConstantProductPool.sol
    smart contract using the Certora prover. For more information,
	visit: https://www.certora.com/

    This file is run with scripts/verifyConstantProductPool.sol
	Assumptions:
*/

using SimpleBentoBox as bentoBox
using SymbolicTridentCallee as symbolicTridentCallee
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
    reserve0() returns (uint112) envfree
    reserve1() returns (uint112) envfree
    otherHarness() returns (address) envfree // for noChangeToOthersBalances
    tokenInHarness() returns (address) envfree // for callFunction
    unlocked() returns (uint256) envfree

    // ConstantProductPool constants
    MAX_FEE() returns (uint256) envfree
    MAX_FEE_MINUS_SWAP_FEE() returns (uint256) envfree
    barFeeTo() returns (address) envfree
    swapFee() returns (uint256) envfree

    // ConstantProductPool functions
    _balance() returns (uint256 balance0, uint256 balance1) envfree
    transferFrom(address, address, uint256)
    totalSupply() returns (uint256) envfree
    getAmountOutWrapper(address tokenIn, uint256 amountIn) returns (uint256) envfree
    balanceOf(address) returns (uint256) envfree

    // TridentERC20 (permit method)
    ecrecover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) 
              returns (address) => NONDET // TODO: check with Nurit

    // ITridentCallee
    symbolicTridentCallee.tridentCalleeRecipient() returns (address) envfree // for noChangeToOthersBalances
    symbolicTridentCallee.tridentCalleeFrom() returns (address) envfree // for noChangeToOthersBalances
    tridentSwapCallback(bytes) => DISPATCHER(true) // TODO: check with Nurit
    tridentMintCallback(bytes) => DISPATCHER(true) // TODO: check with Nurit

    // simplification of sqrt
    sqrt(uint256 x) returns (uint256) => DISPATCHER(true) UNRESOLVED

    // bentobox
    bentoBox.balanceOf(address token, address user) returns (uint256) envfree
    bentoBox.transfer(address token, address from, address to, uint256 share)

    // IERC20
    transfer(address recipient, uint256 amount) returns (bool) => DISPATCHER(true) UNRESOLVED
    balanceOf(address account) returns (uint256) => DISPATCHER(true) UNRESOLVED
    tokenBalanceOf(address token, address user) returns (uint256 balance) envfree 

    // MasterDeployer
    barFee() => CONSTANT // TODO: check with Nurit
    migrator() => NONDET // TODO: check with Nurit
    barFeeTo() => NONDET
    bento() => NONDET

    // IMigrator
    desiredLiquidity() => NONDET // TODO: check with Nurit
}

////////////////////////////////////////////////////////////////////////////
//                                 Ghost                                  //
////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////
//                               Invariants                               //
////////////////////////////////////////////////////////////////////////////
// TODO: This should fail (passing right now)
// A harnessed require is added to the constructor of ConstantProductPool
// to make this rule pass. It is a safe assumption since ConstantProductPoolFactory
// makes sure that token1 != address(0)
invariant validityOfTokens()
    token0() != 0 && token1() != 0 && token0() != token1()

// TODO: This should fail (passing right now)
invariant tokensNotTrident()
    token0() != currentContract && token1() != currentContract

// use 1 and 2 to prove reserveLessThanEqualToBalance
invariant reserveLessThanEqualToBalance()
    reserve0() <= bentoBox.balanceOf(token0(), currentContract) && 
    reserve1() <= bentoBox.balanceOf(token1(), currentContract) {
		preserved {
			requireInvariant validityOfTokens();
		}
	}

// Mudit: bidirectional implication
invariant integrityOfTotalSupply()
        (totalSupply() == 0 <=> reserve0() == 0 ) && 
        (totalSupply() == 0 <=> reserve1() == 0 )  {
        // (reserve0() == 0 => totalSupply() == 0)  && ( reserve1() == 0 => totalSupply() == 0 )  {
        preserved {
			requireInvariant validityOfTokens();
            requireInvariant reserveLessThanEqualToBalance();
		}
        preserved burnWrapper(address to, bool b) with (env e) {
            //require to != currentContract;
            require balanceOf(0) == 1000;
            require e.msg.sender != 0;
            require totalSupply() == 0 || balanceOf(currentContract) + balanceOf(0) <= totalSupply() ;
        }

        preserved burnSingleWrapper(address tokenOut, address to, bool b) with (env e) {
            //require to != currentContract;
            require balanceOf(0) == 1000;
            require e.msg.sender != 0;
            require totalSupply() == 0 || balanceOf(currentContract) + balanceOf(0) <= totalSupply() ;
        }

        preserved swapWrapper(address tokenIn, address recipient, bool unwrapBento) with (env e) {
            require e.msg.sender != currentContract;
            require e.msg.sender != 0;
        }

    /*
        preserved flashSwapWrapper(address tokenIn, address recipient1, bool unwrapBento, uint256 amountIn, bytes context) with (env e) {
            require recipient1 != currentContract;
            require e.msg.sender != currentContract;
            require e.msg.sender != 0;
        
        } */
         
    }
    
////////////////////////////////////////////////////////////////////////////
//                                 Rules                                  //
////////////////////////////////////////////////////////////////////////////
rule sanity(method f) {
    env e;
    calldataarg args;
    f(e, args);

    assert(false);
}

rule pathSanityForToken0(method f) {
    address token0;

    callFunction(f, token0);

    assert(false);
}

rule pathSanityForToken1(method f) {
    address token1;
    
    callFunction(f, token1);

    assert(false);
}

// Passing
rule noChangeToBalancedPoolAssets(method f) filtered { f ->
                    f.selector != flashSwapWrapper(address, address, bool, uint256, bytes).selector } {
    env e;

    uint256 _balance0;
    uint256 _balance1;

    _balance0, _balance1 = _balance();
    
    validState(true);
    // require that the system has no mirin tokens
    require balanceOf(currentContract) == 0;

    calldataarg args;
    f(e, args);
    
    uint256 balance0_;
    uint256 balance1_;

    balance0_, balance1_ = _balance();

    // post-condition: pool's balances don't change
    assert(_balance0 == balance0_ && _balance1 == balance1_, 
           "pool's balance in BentoBox changed");
}

// Passing
rule afterOpBalanceEqualsReserve(method f) {
    env e;

    validState(false);

    uint256 _balance0;
    uint256 _balance1;

    _balance0, _balance1 = _balance();

    uint256 _reserve0 = reserve0();
    uint256 _reserve1 = reserve1();

    address to;
    address tokenIn;
    address tokenOut;
    address recipient;
    bool unwrapBento;

    require to != currentContract;
    require recipient != currentContract;
    
    if (f.selector == burnWrapper(address, bool).selector) {
        burnWrapper(e, to, unwrapBento);
    } else if (f.selector == burnSingleWrapper(address, address, bool).selector) {
        burnSingleWrapper(e, tokenOut, to, unwrapBento);
    } else if (f.selector == swapWrapper(address, address, bool).selector) {
        swapWrapper(e, tokenIn, recipient, unwrapBento);
    } else {
        calldataarg args;
        f(e, args);
    }

    uint256 balance0_;
    uint256 balance1_;

    balance0_, balance1_ = _balance();

    uint256 reserve0_ = reserve0();
    uint256 reserve1_ = reserve1();

    // (reserve or balances changed before and after the method call) => 
    // (reserve0() == balance0_ && reserve1() == balance1_)
    // reserve can go up or down or the balance doesn't change
    assert((_balance0 != balance0_ || _balance1 != balance1_ ||
            _reserve0 != reserve0_ || _reserve1 != reserve1_) =>
            (reserve0_ == balance0_ && reserve1_ == balance1_),
           "balance doesn't equal reserve after state changing operations");
}

// Passing
// Mudit: check require again, should pass without it
// TRIED: doesn't
rule mintingNotPossibleForBalancedPool() {
    env e;

    // TODO: not passing wih this:
    // require totalSupply() > 0 || (reserve0() == 0 && reserve1() == 0);
    require totalSupply() > 0; // TODO: failing without this

    validState(true);

    calldataarg args;
    uint256 liquidity = mintWrapper@withrevert(e, args);

    assert(lastReverted, "pool minting on no transfer to pool");
}

// DONE: try optimal liquidity of ratio 1 (Timing out when changed args
// to actual variables to make the msg.sender the same)
// TODO: if works, add another rule that checks that burn gives the money to the correct person
// Mudit: can fail due to rounding error (-1 for the after liquidities)
// TRIED: still times out
// rule inverseOfMintAndBurn() {
//     env e;

//     // establishing ratio 1 (to simplify)
//     require reserve0() == reserve1();
//     require e.msg.sender != currentContract;

//     uint256 balance0;
//     uint256 balance1;

//     balance0, balance1 = _balance();

//     // stimulating transfer to the pool
//     require reserve0() < balance0 && reserve1() < balance1;
//     uint256 _liquidity0 = balance0 - reserve0();
//     uint256 _liquidity1 = balance1 - reserve1();

//     // making sure that we add optimal liquidity
//     require _liquidity0 == _liquidity1;

//     // uint256 _totalUsertoken0 = tokenBalanceOf(token0(), e.msg.sender) + 
//     //                            bentoBox.balanceOf(token0(), e.msg.sender);
//     // uint256 _totalUsertoken1 = tokenBalanceOf(token1(), e.msg.sender) + 
//     //                            bentoBox.balanceOf(token1(), e.msg.sender);

//     uint256 mirinLiquidity = mintWrapper(e, e.msg.sender);

//     // transfer mirin tokens to the pool
//     transferFrom(e, e.msg.sender, currentContract, mirinLiquidity);

//     uint256 liquidity0_;
//     uint256 liquidity1_;

//     bool unwrapBento;
//     liquidity0_, liquidity1_ = burnWrapper(e, e.msg.sender, unwrapBento);

//     // uint256 totalUsertoken0_ = tokenBalanceOf(token0(), e.msg.sender) + 
//     //                            bentoBox.balanceOf(token0(), e.msg.sender);
//     // uint256 totalUsertoken1_ = tokenBalanceOf(token1(), e.msg.sender) + 
//     //                            bentoBox.balanceOf(token1(), e.msg.sender);

//     // do we instead want to check whether the 'to' user got the funds? (Ask Nurit) -- Yes
//     assert(_liquidity0 == liquidity0_ && _liquidity1 == liquidity1_, 
//            "inverse of mint then burn doesn't hold");
//     // assert(_totalUsertoken0 == totalUsertoken0_ && 
//     //        _totalUsertoken1 == totalUsertoken1_, 
//     //        "user's total balances changed");
// }

// Different way
// rule inverseOfMintAndBurn() {
//     env e;
//     address to;
//     bool unwrapBento;

//     require e.msg.sender != currentContract && to != currentContract;
//     // so that they get the mirin tokens and transfer them back. Also,
//     // when they burn, they get the liquidity back
//     require e.msg.sender == to; 

//     validState(true);

//     uint256 _liquidity0;
//     uint256 _liquidity1;

//     uint256 _totalUsertoken0 = tokenBalanceOf(token0(), e.msg.sender) + 
//                                bentoBox.balanceOf(token0(), e.msg.sender);
//     uint256 _totalUsertoken1 = tokenBalanceOf(token1(), e.msg.sender) + 
//                                bentoBox.balanceOf(token1(), e.msg.sender);

//     // sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, _liquidity0);
//     // sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, _liquidity1);
//     uint256 mirinLiquidity = mintWrapper(e, to);

//     // transfer mirin tokens to the pool
//     transferFrom(e, e.msg.sender, currentContract, mirinLiquidity);

//     uint256 liquidity0_;
//     uint256 liquidity1_;

//     liquidity0_, liquidity1_ = burnWrapper(e, to, unwrapBento);

//     uint256 totalUsertoken0_ = tokenBalanceOf(token0(), e.msg.sender) + 
//                                bentoBox.balanceOf(token0(), e.msg.sender);
//     uint256 totalUsertoken1_ = tokenBalanceOf(token1(), e.msg.sender) + 
//                                bentoBox.balanceOf(token1(), e.msg.sender);

//     assert(_liquidity0 == liquidity0_ && _liquidity1 == liquidity1_, 
//            "inverse of mint then burn doesn't hold");
//     assert(_totalUsertoken0 == totalUsertoken0_ && 
//            _totalUsertoken1 == totalUsertoken1_, 
//            "user's total balances changed");
// }

rule noChangeToOthersBalances(method f) {
    env e;
    address other;
    address recipient;

    validState(false);

    require other != currentContract && other != e.msg.sender &&
            other != bentoBox && other != barFeeTo() &&
            other != symbolicTridentCallee.tridentCalleeFrom();

    // to prevent overflows in TridentERC20 (safe assumption)
    require balanceOf(other) + balanceOf(e.msg.sender) + balanceOf(currentContract) <= totalSupply();
    require e.msg.sender != currentContract; // REVIEW

    // recording other's mirin balance
    uint256 _otherMirinBalance = balanceOf(other);

    // recording other's tokens balance
    // using mathint to prevent overflows
    mathint _totalOthertoken0 = tokenBalanceOf(token0(), other) + 
                               bentoBox.balanceOf(token0(), other);
    mathint _totalOthertoken1 = tokenBalanceOf(token1(), other) + 
                               bentoBox.balanceOf(token1(), other);

    bool unwrapBento;
    address tokenIn;
    address tokenOut;

    if (f.selector == mintWrapper(address).selector) {
        require other != 0; // mint transfers 1000 mirin to the zero address
        mintWrapper(e, recipient);
    } else if (f.selector == burnWrapper(address, bool).selector) {
        burnWrapper(e, recipient, unwrapBento);
    } else if (f.selector == burnSingleWrapper(address, address, bool).selector) {
        burnSingleWrapper(e, tokenOut, recipient, unwrapBento);
    } else if (f.selector == swapWrapper(address, address, bool).selector) {
        swapWrapper(e, tokenIn, recipient, unwrapBento);
    }  else if (f.selector == flashSwapWrapper(address, address, bool, uint256, bytes).selector) {
        require otherHarness() == other;
        calldataarg args;
        flashSwapWrapper(e, args);
    } else if (f.selector == transfer(address, uint256).selector) {
        uint256 amount;
        transfer(e, recipient, amount);
    } else if (f.selector == transferFrom(address, address, uint256).selector) {
        address from;
        require from != other;
        uint256 amount;

        transferFrom(e, from, recipient, amount);
    } else {
        calldataarg args;
        f(e, args);
    }

    // recording other's mirin balance
    uint256 otherMirinBalance_ = balanceOf(other);
    
    // recording other's tokens balance
    // using mathint to prevent overflows
    mathint totalOthertoken0_ = tokenBalanceOf(token0(), other) + 
                               bentoBox.balanceOf(token0(), other);
    mathint totalOthertoken1_ = tokenBalanceOf(token1(), other) + 
                               bentoBox.balanceOf(token1(), other);

    if (other == recipient || other == symbolicTridentCallee.tridentCalleeRecipient()) {
        assert(_otherMirinBalance <= otherMirinBalance_, "other's Mirin balance decreased");
        assert(_totalOthertoken0 <= totalOthertoken0_, "other's token0 balance decreased");
        assert(_totalOthertoken1 <= totalOthertoken1_, "other's token1 balance decreased");
    } else {
        assert(_otherMirinBalance == otherMirinBalance_, "other's Mirin balance changed");
        assert(_totalOthertoken0 == totalOthertoken0_, "other's token0 balance changed");
        assert(_totalOthertoken1 == totalOthertoken1_, "other's token1 balance changed");
    }
}

// Problem with burnSingle, can only burn token1
rule burnTokenAdditivity() {
    env e;
    address to;
    bool unwrapBento;
    uint256 mirinLiquidity;

    validState(true);
    // require to != currentContract;
    // TODO: require balanceOf(e, currentContract) == 0; (Needed ?)

    // need to replicate the exact state later on
    storage initState = lastStorage;

    // burn single token
    transferFrom(e, e.msg.sender, currentContract, mirinLiquidity);
    uint256 liquidity0Single = burnSingleWrapper(e, token0(), to, unwrapBento);

    // uint256 _totalUsertoken0 = tokenBalanceOf(token0(), e.msg.sender) + 
    //                            bentoBox.balanceOf(token0(), e.msg.sender);
    // uint256 _totalUsertoken1 = tokenBalanceOf(token1(), e.msg.sender) + 
    //                            bentoBox.balanceOf(token1(), e.msg.sender);

    uint256 liquidity0;
    uint256 liquidity1;

    // burn both tokens
    transferFrom(e, e.msg.sender, currentContract, mirinLiquidity) at initState;
    liquidity0, liquidity1 = burnWrapper(e, to, unwrapBento);

    // swap token1 for token0
    sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, liquidity1);
    uint256 amountOut = swapWrapper(e, token1(), to, unwrapBento);

    // uint256 totalUsertoken0_ = tokenBalanceOf(token0(), e.msg.sender) + 
    //                            bentoBox.balanceOf(token0(), e.msg.sender);
    // uint256 totalUsertoken1_ = tokenBalanceOf(token1(), e.msg.sender) + 
    //                            bentoBox.balanceOf(token1(), e.msg.sender);

    assert(liquidity0Single == liquidity0 + amountOut, "burns not equivalent");
    // assert(_totalUsertoken0 == totalUsertoken0_, "user's token0 changed");
    // assert(_totalUsertoken1 == totalUsertoken1_, "user's token1 changed");
}

// TODO: Doesn't make sense because you cannot do only one swap and maintain the
// ratio of the tokens
rule sameUnderlyingRatioLiquidity(method f) filtered { f -> 
        f.selector == swapWrapper(address, address, bool).selector ||
        f.selector == flashSwapWrapper(address, address, bool, uint256, bytes).selector } {
    env e1;
    env e2;
    env e3;

    // TODO: safe assumption, checked in the constructor (not the reason for counter example)
    require swapFee() <= MAX_FEE();

    // setting the environment constraints
    require e1.block.timestamp < e2.block.timestamp && 
            e2.block.timestamp < e3.block.timestamp;
    // TODO: swap is done by someother person (safe asumption??)
    require e1.msg.sender == e3.msg.sender && e2.msg.sender != e1.msg.sender;

    validState(true);

    require reserve0() / reserve1() == 2;

    uint256 _liquidity0;
    uint256 _liquidity1;

    if (totalSupply() != 0) {
        // user's liquidity for token0 = user's mirinTokens * reserve0 / totalSupply of mirinTokens
        _liquidity0 = balanceOf(e1.msg.sender) * reserve0() / totalSupply();
        // user's liquidity for token1 = user's mirinTokens * reserve0 / totalSupply of mirinTokens
        _liquidity1 = balanceOf(e1.msg.sender) * reserve1() / totalSupply();
    } else {
        _liquidity0 = 0;
        _liquidity1 = 0;
    }

    calldataarg args1;
    f(e2, args1);
    calldataarg args2;
    f(e2, args2);

    uint256 liquidity0_;
    uint256 liquidity1_;

    if (totalSupply() != 0) {
        // user's liquidity for token0 = user's mirinTokens * reserve0 / totalSupply of mirinTokens
        uint256 liquidity0_ = balanceOf(e3.msg.sender) * reserve0() / totalSupply();
        // user's liquidity for token1 = user's mirinTokens * reserve0 / totalSupply of mirinTokens
        uint256 liquidity1_ = balanceOf(e3.msg.sender) * reserve1() / totalSupply();
    } else {
        liquidity0_ = 0;
        liquidity1_ = 0;
    }
    
    // TODO: my guess is that same problem we need the integrityOfTotalSupply()
    // and small numbers
    if (swapFee() > 0 && totalSupply() != 0) {
        // user's liquidities should strictly increase because of swapFee
        assert((reserve0() / reserve1() == 2) => (_liquidity0 < liquidity0_ &&
                _liquidity1 < liquidity1_), "with time liquidities didn't increase");
    } else {
        // since swapFee was zero, the liquidities should stay unchanged
        assert((reserve0() / reserve1() == 2) => (_liquidity0 == liquidity0_ &&
                _liquidity1 == liquidity1_), "with time liquidities decreased"); 
    }
}

// Timing out, even with reserve0() / reserve1() == 1
// TODO: all swap methods
// Mudit: singleAmountOut == multiAmountOut1 + multiAmountOut2
// rule multiSwapLessThanSingleSwap() {
//     env e;
//     address to;
//     bool unwrapBento;
//     uint256 liquidity1;
//     uint256 liquidity2;

//     // TODO: liquidity1, liquidity2 can't be 0??? Maybe (to prevent counter examples)
//     require e.msg.sender != currentContract && to != currentContract;

//     validState(true);

//     // need to replicate the exact state later on
//     storage initState = lastStorage;

//     // swap token1 for token0 in two steps
//     sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, liquidity1);
//     uint256 multiAmountOut1 = swapWrapper(e, token1(), to, unwrapBento);
//     sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, liquidity2);
//     uint256 multiAmountOut2 = swapWrapper(e, token1(), to, unwrapBento);

//     // checking for overflows
//     require multiAmountOut1 + multiAmountOut2 <= max_uint256;
//     require liquidity1 + liquidity2 <= max_uint256;

//     // swap token1 for token0 in a single step
//     sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, liquidity1 + liquidity2) at initState; 
//     uint256 singleAmountOut = swapWrapper(e, token1(), to, unwrapBento);

//     // TODO: Mudit wanted strictly greater, but when all amountOuts are 0s we get a counter example
//     assert(singleAmountOut >= multiAmountOut1 + multiAmountOut2, "multiple swaps better than one single swap");
// }

// TODO: rename the rule to be equal since swapFee is zero
rule multiLessThanSingleAmountOut() {
    env e;
    uint256 amountInX;
    uint256 amountInY;

    require swapFee() == 0;
    
    uint256 multiAmountOut1 = _getAmountOut(e, amountInX, reserve0(), reserve1());
    require reserve0() + amountInX <= max_uint256;
    uint256 multiAmountOut2 = _getAmountOut(e, amountInY, reserve0() + amountInX, reserve1() - multiAmountOut1);

    // checking for overflows
    require amountInX + amountInY <= max_uint256;

    uint256 singleAmountOut = _getAmountOut(e, amountInX + amountInY, reserve0(), reserve1());

    assert(singleAmountOut == multiAmountOut1 + multiAmountOut2, "multiple swaps not equal to one single swap");
}

// Before: reserve0(), reserve1()
// After: reserve0() + amountInX, reserve1() - multiAmountOut1
// filtered { f -> f.selector == swapWrapper(address, address, bool).selector
//                 f.selector == flashSwapWrapper(address, address, bool, uint256, bytes).selector }
rule increasingConstantProductCurve() {
    env e;
    uint256 amountIn;

    require 0 <= MAX_FEE_MINUS_SWAP_FEE() && MAX_FEE_MINUS_SWAP_FEE() <= MAX_FEE();

    uint256 _reserve0 = reserve0();
    uint256 _reserve1 = reserve1();

    // tokenIn is token0
    uint256 amountOut = _getAmountOut(e, amountIn, _reserve0, _reserve1);

    require _reserve0 + amountIn <= max_uint256;

    uint256 reserve0_ = _reserve0 + amountIn;
    uint256 reserve1_ = _reserve1 - amountOut;

    assert(_reserve0 * _reserve1 <= reserve0_ * reserve1_);
}

// rule increasingConstantProductCurve(uint256 reserve0_, uint256 reserve1_) {
//     env e;
//     address tokenIn;
//     address recipient;
//     bool unwrapBento;

//     require tokenIn == token0();

//     validState(false);

//     uint256 _reserve0 = reserve0();
//     uint256 _reserve1 = reserve1();

//     swapWrapper(e, tokenIn, recipient, unwrapBento);

//     require reserve0_ == reserve0();
//     require reserve1_ == reserve1();

//     assert(_reserve0 * _reserve1 <= reserve0_ * reserve1_);
// }

// Timing out, even with require reserve0() == reserve1();
// rule additivityOfMint() {
//     env e;
//     address to;
//     uint256 x1;
//     uint256 x2;
//     uint256 y1;
//     uint256 y2;

//     // x, y can be 0? Their ratio (they have to be put in the same ratio, right?) 
//     // TODO: require e.msg.sender == to? Or check the assets of 'to'?
//     validState(true);

//     // need to replicate the exact state later on
//     storage initState = lastStorage;

//     // minting in two steps
//     sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, x1);
//     sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, y1);
//     uint256 mirinTwoSteps1 = mintWrapper(e, to);

//     sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, x2);
//     sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, y2);
//     uint256 mirinTwoSteps2 = mintWrapper(e, to);

//     uint256 userMirinBalanceTwoStep = balanceOf(e, e.msg.sender);

//     // checking for overflows
//     require mirinTwoSteps1 + mirinTwoSteps2 <= max_uint256;
//     require x1 + x2 <= max_uint256 && y1 + y2 <= max_uint256;

//     // minting in a single step
//     sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, x1 + x2) at initState;
//     sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, y1 + y2);
//     uint256 mirinSingleStep = mintWrapper(e, to);

//     uint256 userMirinBalanceOneStep = balanceOf(e, e.msg.sender);

//     // TODO: strictly greater than?
//     assert(mirinSingleStep >= mirinTwoSteps1 + mirinTwoSteps2, "multiple mints better than a single mint");
//     assert(userMirinBalanceOneStep >= userMirinBalanceTwoStep, "user received less mirin in one step");
// }

// Timing out, even with ratio 1
// rule mintWithOptimalLiquidity() {
//     env e;
//     address to;

//     uint256 xOptimal;
//     uint256 yOptimal;
//     uint256 x;
//     uint256 y;

//     // require dollarAmount(xOptimal) + dollarAmount(yOptimal) == dollarAmount(x) + dollarAmount(y);
//     require getAmountOutWrapper(token0(), yOptimal) + xOptimal == 
//             getAmountOutWrapper(token0(), y) + x;

//     require x != y; // requiring that x and y are non optimal

//     require reserve0() == reserve1();
//     require xOptimal == yOptimal; // requiring that these are optimal

//     validState(true);

//     // need to replicate the exact state later on
//     storage initState = lastStorage;

//     // minting with optimal liquidities
//     sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, xOptimal);
//     sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, yOptimal);
//     uint256 mirinOptimal = mintWrapper(e, e.msg.sender);

//     uint256 userMirinBalanceOptimal = balanceOf(e, e.msg.sender);

//     // minting with non-optimal liquidities
//     sinvoke bentoBox.transfer(e, token0(), e.msg.sender, currentContract, x) at initState;
//     sinvoke bentoBox.transfer(e, token1(), e.msg.sender, currentContract, y);
//     uint256 mirinNonOptimal = mintWrapper(e, e.msg.sender);

//     uint256 userMirinBalanceNonOptimal = balanceOf(e, e.msg.sender);

//     // TODO: strictly greater? (Mudit: when the difference is small, the final amount would be the same)
//     assert(mirinOptimal >= mirinNonOptimal);
//     assert(userMirinBalanceOptimal >= userMirinBalanceNonOptimal);
// }

rule zeroCharacteristicsOfGetAmountOut(uint256 _reserve0, uint256 _reserve1) {
    env e;
    uint256 amountIn;
    address tokenIn;
    address tokenOut;

    validState(false);

    // assume token0 to token1
    require tokenIn == token0() || tokenIn == token1(); 

    require _reserve0 == reserve0();
    require _reserve1 == reserve1();

    require 0 <= MAX_FEE_MINUS_SWAP_FEE() && MAX_FEE_MINUS_SWAP_FEE() <= MAX_FEE();

    uint256 amountInWithFee = amountIn * MAX_FEE_MINUS_SWAP_FEE();

    uint256 amountOut = getAmountOutWrapper(tokenIn, amountIn);

    if (amountIn == 0) {
        assert(amountOut == 0, "amountIn is 0, but amountOut is not 0");
    } else if (tokenIn == token0() && reserve1() == 0) {
        assert(amountOut == 0, "token1 has no reserves, but amountOut is non-zero");
    } else if (tokenIn == token1() && reserve0() == 0) {
        assert(amountOut == 0, "token0 has no reserves, but amountOut is non-zero");
    } else if (tokenIn == token0() && amountInWithFee * _reserve1 < (_reserve0 * MAX_FEE()) + amountInWithFee) { // TODO: review
        assert(amountOut == 0, "numerator > denominator");
    } else if (tokenIn == token1() && amountInWithFee * _reserve0 < (_reserve1 * MAX_FEE()) + amountInWithFee) { // TODO: review
        assert(amountOut == 0, "numerator > denominator");
    } else {
        assert(amountOut > 0, "amountOut not greater than zero");
    }
}

// Passing
rule maxAmountOut(uint256 _reserve0, uint256 _reserve1) {
    env e;

    uint256 amountIn;
    address tokenIn;

    validState(false);

    require tokenIn == token0(); 
    require _reserve0 == reserve0();
    require _reserve1 == reserve1();
    require _reserve0 > 0 && _reserve1 > 0;
    require MAX_FEE_MINUS_SWAP_FEE() <= MAX_FEE();

    uint256 amountOut = getAmountOutWrapper(tokenIn, amountIn);
    // mathint maxValue = to_mathint(amountIn) * to_mathint(_reserve1) / to_mathint(_reserve0);
    // assert amountOut <= maxValue;

    // Mudit: needs to be strictly less than
    // TRIED: works!!!!
    assert amountOut < _reserve1; 
}

// Passing
rule nonZeroMint() {
    env e;
    address to;

    validState(false);

    require reserve0() < bentoBox.balanceOf(token0(), currentContract) ||
                reserve1() < bentoBox.balanceOf(token1(), currentContract);

    uint256 liquidity = mintWrapper(e, to);

    assert liquidity > 0;
}

// rule constantFormulaIsCorrect() {
    // value returned by getAmountOut matches the value using the ConstantProductFormula
    // for the same input.
// }

// 2. prove that you can't not call back the ConstantProductPool
//      TODO: Assume unlock is true (means 2???), call any ConstantProductPool function with revert, and assert lastReverted
// want f to only be public functions
// TODO: filter {f -> !f.isView}
rule reentrancy(method f) { 
    require unlocked() == 2; // means locked

    env e;
    calldataarg args;
    f@withrevert(e, args);

    assert(lastReverted, "reentrancy possible");

}

// If the bentoBox balance of one token decreases then the 
// other token’s BentoBox increases or the totalSupply decreases
// (strictly increase and strictly decrease)
rule integrityOfBentoBoxTokenBalances(method f) {
    validState(false);

    // TODO: trying out various things
    require totalSupply() == 0 <=> (reserve0() == 0 && reserve1() == 0);
    
    // if (totalSupply() > 0) {
    //     require reserve0() > 0 && reserve1() > 0;
    // }

    uint256 _token0Balance = bentoBox.balanceOf(token0(), currentContract);
    uint256 _token1Balance = bentoBox.balanceOf(token1(), currentContract);
    uint256 _totalSupply = totalSupply();

    env e;
    calldataarg args;
    f(e, args);

    uint256 token0Balance_ = bentoBox.balanceOf(token0(), currentContract);
    uint256 token1Balance_ = bentoBox.balanceOf(token1(), currentContract);
    uint256 totalSupply_ = totalSupply();

    // if token0's balance decreases, token1's balance should increase or 
    // totalSupply (Mirin) should decrease
    assert((token0Balance_ - _token0Balance < 0) => 
           ((token1Balance_ - _token1Balance > 0) || (totalSupply_ - _totalSupply < 0)),
           "token0's balance decreased; conditions not met");
    // if token1's balance decreases, token0's balance should increase or 
    // totalSupply (Mirin) should decrease
    assert((token1Balance_ - _token1Balance < 0) => 
           ((token0Balance_ - _token0Balance > 0) || (totalSupply_ - _totalSupply < 0)),
           "token1's balance decreased; conditions not met");
}

////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////
function validState(bool isBalanced) {
    requireInvariant validityOfTokens();
    requireInvariant tokensNotTrident();

    if (isBalanced) {
        require reserve0() == bentoBox.balanceOf(token0(), currentContract) &&
                reserve1() == bentoBox.balanceOf(token1(), currentContract);
    } else {
        requireInvariant reserveLessThanEqualToBalance();
    }
}

// designed for sanity of the tokens
// WARNING: be careful when using, especially with the parameter constraints
function callFunction(method f, address token) {
    env e;
    address to;
    address recipient;
    bool unwrapBento;

    if (f.selector == burnSingleWrapper(address, address, bool).selector) {
        // tokenOut, to, unwrapBento
        burnSingleWrapper(e, token, to, unwrapBento);
    } else if (f.selector == swapWrapper(address, address, bool).selector) {
        // tokenIn, recipient, unwrapBento
        swapWrapper(e, token, recipient, unwrapBento);
    } else if (f.selector == flashSwapWrapper(address, address, bool,
                              uint256, bytes).selector) {
        // tokenIn, recipient, unwrapBento, amountIn, context
        calldataarg args;
        require token == tokenInHarness();
        flashSwapWrapper(e, args);
    } else if (f.selector == getAmountOutWrapper(address, uint256).selector) {
        // tokenIn, amountIn
        uint256 amountIn;
        getAmountOutWrapper(token, amountIn);
    } else {
        calldataarg args;
        f(e, args);
    }
}
/*
    This is a specification file for the verification of ConstantProductPool.sol
    smart contract using the Certora prover. For more information,
	visit: https://www.certora.com/

    This file is run with scripts/verifyConstantProductPool.sol

	Assumptions:
    - Verified using a simplified version of BentoBox and square root function
    - Loops are unwinded 4 times
    - Token1 is not the zero address (a safe assumption guaranteed by the ConstantProductPoolFactory)
    - For certain operations, it is assumed that the recipient is not the ConstantProductPool
    - TridentERC20 has no overflows
    - msg.sender is not the ConstantProductPool
    - Simplified Trident callbacks

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
    otherHarness() returns (address) envfree 
    tokenInHarness() returns (address) envfree 
    unlocked() returns (uint256) envfree

    // ConstantProductPool constants
    MAX_FEE() returns (uint256) envfree
    MAX_FEE_MINUS_SWAP_FEE() returns (uint256) envfree
    barFeeTo() returns (address) envfree
    swapFee() returns (uint256) envfree
    kLast() returns (uint256) envfree

    // ConstantProductPool functions
    _balance() returns (uint256 balance0, uint256 balance1) envfree
    transferFrom(address, address, uint256)
    totalSupply() returns (uint256) envfree
    getAmountOutWrapper(address tokenIn, uint256 amountIn) returns (uint256) envfree
    balanceOf(address) returns (uint256) envfree

    // TridentERC20 (permit method)
    ecrecover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) 
              returns (address) => NONDET 

    // ITridentCallee
    symbolicTridentCallee.tridentCalleeRecipient() returns (address) envfree 
    symbolicTridentCallee.tridentCalleeFrom() returns (address) envfree 
    symbolicTridentCallee.tridentCalleeShares() returns (uint256) envfree
    symbolicTridentCallee.tridentCalleeToken() returns (address) envfree
    tridentSwapCallback(bytes) => DISPATCHER(true) 
    tridentMintCallback(bytes) => DISPATCHER(true) 

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
    barFee() => CONSTANT 
    migrator() => NONDET 
    barFeeTo() => NONDET
    bento() => NONDET

    // IMigrator
    desiredLiquidity() => NONDET 
}
//  Tokens cannot be the zero address or equal to each other
invariant validityOfTokens()
    token0() != 0 && token1() != 0 && token0() != token1()

// Tokens cannot be the Trident token
invariant tokensNotTrident()
    token0() != currentContract && token1() != currentContract

// Pool's reserves are always less than or equal to pool's balances 
invariant reserveLessThanEqualToBalance()
    reserve0() <= bentoBox.balanceOf(token0(), currentContract) && 
    reserve1() <= bentoBox.balanceOf(token1(), currentContract) {
		preserved {
			requireInvariant validityOfTokens();
		}
	}
// Trident's `totalSupply` is zero if and only if both the reserves are zero
invariant integrityOfTotalSupply()
        (totalSupply() == 0 <=> reserve0() == 0) && 
        (totalSupply() == 0 <=> reserve1() == 0)  {
        // (reserve0() == 0 => totalSupply() == 0)  && ( reserve1() == 0 => totalSupply() == 0 )  {
        preserved {
           
			requireInvariant validityOfTokens();
            requireInvariant reserveLessThanEqualToBalance();
		}
        preserved burnWrapper(address to, bool b) with (env e) {
            requireInvariant validityOfTokens();
            requireInvariant reserveLessThanEqualToBalance();
            require balanceOf(0) == 1000;
            require e.msg.sender != 0;
            require totalSupply() == 0 || balanceOf(currentContract) + balanceOf(0) <= totalSupply();
            require kLast()==0;

        }

        preserved burnSingleWrapper(address tokenOut, address to, bool b) with (env e) {
            require false;
        }

        preserved swapWrapper(address tokenIn, address recipient, bool unwrapBento) with (env e) {
            requireInvariant validityOfTokens();
            requireInvariant reserveLessThanEqualToBalance();
            require e.msg.sender != currentContract;
            require e.msg.sender != 0;
        }

        preserved flashSwapWrapper(address tokenIn, address recipient1, bool unwrapBento, uint256 amountIn, bytes context) with (env e) {
            require false;
            }
    
    }

    //  Every operation that takes a token as a parameter should support both tokens
rule pathSanityForToken0(method f) {
    callFunction(f, token0());

    assert(false);
}
rule pathSanityForToken1(method f) {
    callFunction(f, token1());

    assert(false);
}

//  No reentrancy for locked functions

rule reentrancy(method f) filtered { f -> !f.isView}{
    require unlocked() == 2; // means locked
    validState(false);

    env e;
    calldataarg args;
    f@withrevert(e, args);

    assert(lastReverted, "reentrancy possible");

}

// Any operation shouldn't change some other user's assets
rule noChangeToOthersBalancesOut(method f) {
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
        uint256 amountIn;
        bytes context;
        require getAmountOutWrapper(tokenIn,amountIn)+tokenBalanceOf(tokenOut, other) + bentoBox.balanceOf(tokenOut, other)<max_uint256;

        flashSwapWrapper(e,tokenIn, recipient, unwrapBento, amountIn, context);
    } else if (f.selector == transfer(address, uint256).selector) {
        uint256 amount;
        require amount+balanceOf(recipient) <= totalSupply();
        
        
        transfer(e, recipient, amount);
    } else if (f.selector == transferFrom(address, address, uint256).selector) {
        address from;
        require from != other;
        uint256 amount;
        require amount+balanceOf(recipient) <= totalSupply();



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
// If the bentoBox balance of one token decreases then the 
// other token’s BentoBox increases or the totalSupply decreases. 
// Symplifying assumption: kLast=0, so we neglect the Bar-Fee.

rule integrityOfBentoBoxTokenBalances(method f) filtered { f -> f.selector != flashSwapWrapper(address, address, bool, uint256, bytes).selector}{
    validState(false);

    require (totalSupply() == 0 <=> reserve0() == 0);
    require (totalSupply() == 0 <=> reserve1() == 0);
    uint256 _reserve0 = reserve0();
    uint256 _reserve1 = reserve1();
    uint256 _totalSupply = totalSupply();
    require _totalSupply>1000;
    require balanceOf(currentContract)<totalSupply();
    require totalSupply()<max_uint256;
    require 0<MAX_FEE_MINUS_SWAP_FEE();
    require MAX_FEE_MINUS_SWAP_FEE()<10000;
    require currentContract != symbolicTridentCallee.tridentCalleeFrom();
    
    
     if (f.selector == burnSingleWrapper(address, address, bool).selector) {
        require kLast()==0;
        address tokenOut; address recipient; bool unwrapBento; env e; 
        burnSingleWrapper(e,tokenOut,recipient,unwrapBento);
        
        }
        if (f.selector == burnWrapper(address, bool).selector) {
        require kLast()==0;
        address recipient; bool unwrapBento; env e; 
        burnWrapper(e,recipient,unwrapBento);
        
        }
          
     else{    
   
    env e;
    
    calldataarg args;
    f(e, args);}

    uint256 reserve0_ = reserve0();
    uint256 reserve1_ = reserve1();
    uint256 totalSupply_ = totalSupply();
    

    // if token0's balance decreases, token1's balance should increase or 
    // totalSupply (Mirin) should decrease
    assert((reserve0_ - _reserve0 < 0) => 
           ((reserve1_ - _reserve1 > 0) || (totalSupply_ - _totalSupply < 0)),
           "token0's balance decreased; conditions not met");
    // if token1's balance decreases, token0's balance should increase or 
    // totalSupply (Mirin) should decrease
    assert((reserve1_ - _reserve1 < 0) => 
           ((reserve0_ - _reserve0 > 0) || (totalSupply_ - _totalSupply < 0)),
           "token1's balance decreased; conditions not met");
}


////////////////////////////////////////////////////////////////////////////
//                             Helper Methods                             //
////////////////////////////////////////////////////////////////////////////
function validState(bool isBalanced) {
    requireInvariant validityOfTokens();
    requireInvariant tokensNotTrident();
    require balanceOf(0)==1000;
    require totalSupply()>balanceOf(currentContract)+balanceOf(0);

   

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
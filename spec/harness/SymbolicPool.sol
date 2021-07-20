
pragma solidity ^0.8.2;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/interfaces/IPool.sol";
import "../../contracts/interfaces/IBentoBox.sol";
import "../../contracts/pool/MirinERC20.sol";


/* This is a symbolic pool used for verification with Certora Prover.
variables are symbolic so no need to initialize, the Prover will simulate all possible values

*/



contract SymbolicPool is IPool, MirinERC20 {
    IBentoBoxV1 public bento;

    // There is a set of tokens this pool supports
    IERC20[] public tokens;

    // the amount of holding the pool has for each token[i]
    mapping(address => uint256) public reserves; 

    // a symbolic representation of amountOut for a particular set of
    //    (tokenIn, tokenOut, reserve[tokenIn], reserve[tokenOut], amountIn)
    mapping (address => mapping (address => mapping (uint256 => mapping( uint256 => mapping( uint256 => uint256))))) computedAmountOut; 


    // a symbolic representation of amountOut for a particular set of
    //    (tokenIn, tokenOut, reserve[tokenIn], reserve[tokenOut], amountOut)
    mapping (address => mapping (address => mapping (uint256 => mapping( uint256 => mapping( uint256 => uint256))))) computedAmountIn; 

    // a function to correlate between the two different mappings  
    function assumptionValidAmountInAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) public view {
        uint256 amountInFromMapping = computedAmountOut[tokenIn][tokenOut][reserves[tokenIn]][reserves[tokenOut]][amountOut];
        require (amountIn == amountInFromMapping);
        require (computedAmountIn[tokenIn][tokenOut][reserves[tokenIn]][reserves[tokenOut]][amountInFromMapping] == amountOut);
    }

    function swapWithoutContext(address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountIn, uint256 amountOut) external override returns(uint256 finalAmountOut) {
       return basicSwap(tokenIn, tokenOut, recipient, amountIn);
    }

    function swapExactIn(address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountIn) external override returns(uint256 finalAmountOut) {
        return basicSwap(tokenIn, tokenOut, recipient, amountIn);
    }

    function swapExactOut(address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountOut) external override {
        uint256 amountIn = computedAmountIn[tokenIn][tokenOut][reserves[tokenIn]][reserves[tokenOut]][amountOut];
        assumptionValidAmountInAmountOut(tokenIn, tokenOut, amountIn, amountOut);
        basicSwap(tokenIn, tokenOut, recipient, amountIn);
    }

    function swapWithContext(address tokenIn, address tokenOut, bytes calldata context, address recipient, bool unwrapBento, uint256 amountIn, uint256 amountOut) external override returns(uint256 finalAmountOut) {
        //todo - add call to another contract
        return basicSwap(tokenIn, tokenOut, recipient,amountIn);
    }

    function basicSwap(address tokenIn, address tokenOut, address recipient, uint256 amountIn) internal  returns(uint256 finalAmountOut) {
        // checking swapRouter, it should pass in amountIn of tokenIn
        assert ( bento.balanceOf(IERC20(tokenIn),address(this)) - reserves[tokenIn] >= amountIn );

        // a symbolic value representing the computed amountOut which is a function of the current reserve state and amountIn
        finalAmountOut = computedAmountOut[tokenIn][tokenOut][reserves[tokenIn]][reserves[tokenOut]][amountIn];
        //assumption - finalAmoutOut is not zero for non zero amountIn
        require (finalAmountOut != 0 || amountIn == 0);
        // transfer to  recipient
        bento.transfer(IERC20(tokenOut), address(this), recipient, finalAmountOut);

    }

    function getOptimalLiquidityInAmounts(liquidityInput[] calldata liquidityInputs) external override returns(liquidityAmount[] memory liquidityOptimal) {

    }

    
    function mint(address to) external override returns(uint256 liquidity) {
    
    }

}
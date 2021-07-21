
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
    mapping(IERC20 => uint256) public reserves; 

    
    // a symbolic representation of fixed conversion ratio between each two tokens
    mapping (IERC20 => mapping (IERC20 => uint256)) public rates; 
    
     

    
    function swapWithoutContext(address tokenIn, address tokenOut, address recipient, bool unwrapBento) external override returns(uint256 finalAmountOut) {
        IERC20 _tokenIn = IERC20(tokenIn);
        uint256 amountIn = bento.balanceOf(_tokenIn,address(this)) - reserves[_tokenIn];
        return basicSwap(_tokenIn, IERC20(tokenOut), recipient, amountIn);
    }

    function swapWithContext(address tokenIn, address tokenOut, bytes calldata context, address recipient, bool unwrapBento, uint256 amountIn) external override returns(uint256 finalAmountOut) {
        //todo - add call to another contract
        return basicSwap(IERC20(tokenIn), IERC20(tokenOut), recipient,amountIn);
    }

    function basicSwap(IERC20 tokenIn, IERC20 tokenOut, address recipient, uint256 amountIn) internal  returns(uint256 finalAmountOut) {
        // checking swapRouter, it should pass in amountIn of tokenIn
        assert ( bento.balanceOf(tokenIn,address(this)) - reserves[tokenIn] >= amountIn );

        // a symbolic value representing the computed amountOut which is a function of the current reserve state and amountIn
        finalAmountOut = rates[tokenIn][tokenOut]*amountIn;
        //assumption - finalAmoutOut is not zero for non zero amountIn
        require (rates[tokenIn][tokenOut] != 0);
        // transfer to  recipient
        bento.transfer(tokenOut, address(this), recipient, finalAmountOut);
        update();

    }

    function getOptimalLiquidityInAmounts(liquidityInput[] calldata liquidityInputs) external override returns(liquidityAmount[] memory liquidityOptimal) {

    }

      
    // a basic one to one mapping
    function mint(address to) external override returns(uint256 liquidity) {
        for( uint i = 0 ; i < tokens.length ; i++) 
           liquidity += bento.balanceOf(IERC20(tokens[i]),address(this)) - reserves[tokens[i]];
        _mint(to, liquidity);
        update(); 
    }

    // returns amount of share in bentobox
    function burn(address to, bool unwrapBento) external override returns (liquidityAmount[] memory withdrawnAmounts) {
        //how much liquidity passed to the pool for burning
        uint256 liquidity = balanceOf[address(this)];
        _burn(address(this), liquidity);
        uint256 split = liquidity / tokens.length; 
        withdrawnAmounts = new liquidityAmount[](tokens.length);
        for( uint i = 0 ; i < tokens.length ; i++) {
            bento.transfer(tokens[i], address(this), to, split);
            withdrawnAmounts[i] = liquidityAmount({token: address(tokens[i]), amount: split});
        }
        update();
    }

    function burnLiquiditySingle(address tokenOut, address to, bool unwrapBento) external override returns (uint256 amount) {
        uint256 amount = balanceOf[address(this)];
        _burn(address(this), amount);
        bento.transfer(IERC20(tokenOut), address(this), to, amount);
        update();
    }

    function update() internal {
        for( uint i = 0 ; i < tokens.length ; i++) {
            reserves[tokens[i]] = bento.balanceOf(tokens[i],address(this));
        }
    }

    function tokensLength() public returns (uint256) {
        return tokens.length;
    }
    
}
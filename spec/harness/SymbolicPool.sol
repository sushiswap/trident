/* 
    This is a symbolic pool used for verification with Certora Prover.
    variables are symbolic so no need to initialize them, the Prover will
    simulate all possible values
*/

pragma solidity ^0.8.2;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/interfaces/IPool.sol";
import "../../contracts/interfaces/IBentoBox.sol";
import "../../contracts/pool/MirinERC20.sol";

contract SymbolicPool is IPool, MirinERC20 {
    IBentoBoxV1 public bento;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public token2;
    // There is a set of tokens this pool supports
    // the amount of holding the pool has for each token[i]
    mapping(IERC20 => uint256) public reserves; 
    // a symbolic representation of fixed conversion ratio between each two tokens
    mapping (IERC20 => mapping (IERC20 => uint256)) public rates; 

    uint256 internal constant NUM_TOKENS = 3;
    
    function swapWithoutContext(address tokenIn, address tokenOut,
                                address recipient, bool unwrapBento) 
                                external override returns(uint256 finalAmountOut) {
        IERC20 _tokenIn = IERC20(tokenIn);

        uint256 amountIn = bento.balanceOf(_tokenIn, address(this)) - reserves[_tokenIn];

        return basicSwap(_tokenIn, IERC20(tokenOut), recipient, amountIn);
    }

    function swapWithContext(address tokenIn, address tokenOut,
                             bytes calldata context, address recipient,
                             bool unwrapBento, uint256 amountIn)
                            external override returns(uint256 finalAmountOut) {
        // TODO: add call to another contract
        return basicSwap(IERC20(tokenIn), IERC20(tokenOut), recipient,amountIn);
    }

    function basicSwap(IERC20 tokenIn, IERC20 tokenOut, address recipient,
                       uint256 amountIn) internal  returns(uint256 finalAmountOut) {
        // checking swapRouter, it should pass in amountIn of tokenIn
        assert(bento.balanceOf(tokenIn,address(this)) - reserves[tokenIn] >= amountIn);

        // a symbolic value representing the computed amountOut which is a
        // function of the current reserve state and amountIn
        finalAmountOut = rates[tokenIn][tokenOut] * amountIn;
        // assumption - finalAmoutOut is not zero for non zero amountIn
        require(rates[tokenIn][tokenOut] != 0);

        // transfer to  recipient
        bento.transfer(tokenOut, address(this), recipient, finalAmountOut);
        update(tokenIn);
        update(tokenOut);
    }

    function getOptimalLiquidityInAmounts(liquidityInput[] calldata liquidityInputs) 
            external override returns(liquidityAmount[] memory liquidityOptimal) { }

    // a basic one to one mapping
    function mint(address to) external override returns(uint256 liquidity) {
        liquidity =  bento.balanceOf(IERC20(token0),address(this)) - reserves[IERC20(token0)];
        liquidity +=  bento.balanceOf(IERC20(token1),address(this)) - reserves[IERC20(token1)];
        liquidity +=  bento.balanceOf(IERC20(token2),address(this)) - reserves[IERC20(token2)];
        _mint(to, liquidity);
        update(token0); 
        update(token1);
        update(token2);  
    }

    // returns amount of shares in bentobox
    // TODO: not using unwrapBento ask Nurit
    function burn(address to, bool unwrapBento) 
            external override returns (liquidityAmount[] memory withdrawnAmounts) {
        // how much liquidity passed to the pool for burning
        uint256 liquidity = balanceOf[address(this)];
        
        _burn(address(this), liquidity);
        
        uint256 split = getSplitValue(liquidity); 
        
        withdrawnAmounts = new liquidityAmount[](NUM_TOKENS);

        bento.transfer(token0, address(this), to, split);
        withdrawnAmounts[0] = liquidityAmount({token: address(token0), amount: split});
        
        bento.transfer(token1, address(this), to, split);
        withdrawnAmounts[1] = liquidityAmount({token: address(token1), amount: split});

        bento.transfer(token2, address(this), to, split);
        withdrawnAmounts[2] = liquidityAmount({token: address(token2), amount: split});
        
        update(token0); 
        update(token1);
        update(token2);  
    }

    function burnLiquiditySingle(address tokenOut, address to, bool unwrapBento)
            external override returns (uint256 amount) {
        uint256 amount = balanceOf[address(this)];

        _burn(address(this), amount);

        bento.transfer(IERC20(tokenOut), address(this), to, amount);

        update(IERC20(tokenOut));
    }

    function update(IERC20 token) internal {
        reserves[token] = bento.balanceOf(token,address(this));
    }

    function tokensLength() public returns (uint256) {
        return NUM_TOKENS; 
    }

    function isBalanced() public returns (bool res) {
       return   reserves[token0] == bento.balanceOf(token0,address(this)) &&
                reserves[token1] == bento.balanceOf(token1,address(this)) &&
                reserves[token2] == bento.balanceOf(token2,address(this));
    }
    
    
    function getReserveOfToken(IERC20 token) public returns (uint256) {
        return reserves[token];

    }

    function getSplitValue(uint liquidity) private returns(uint256) {
        return liquidity /  NUM_TOKENS; 
        
    }
}
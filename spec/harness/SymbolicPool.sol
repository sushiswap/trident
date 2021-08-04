/* 
    This is a symbolic pool used for verification with Certora Prover.
    variables are symbolic so no need to initialize them, the Prover will
    simulate all possible values
*/

pragma solidity ^0.8.2;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/interfaces/IPool.sol";
import "../../contracts/interfaces/IBentoBoxMinimal.sol";
import "../../contracts/pool/TridentERC20.sol";

contract SymbolicPool is IPool, TridentERC20 {
    IBentoBoxMinimal public bento;
    address public token0;
    address public token1;
    address public token2;
    // There is a set of tokens this pool supports
    // the amount of holding the pool has for each token[i]
    mapping(address => uint256) public reserves; 
    // a symbolic representation of fixed conversion ratio between each two tokens
    mapping (address => mapping (address => uint256)) public rates; 

    uint256 internal constant NUM_TOKENS = 3;
    
    function swapWithoutContext(address tokenIn, address tokenOut,
                                address recipient, bool unwrapBento) 
                                external override returns(uint256 finalAmountOut) {
        
        uint256 amountIn = bento.balanceOf(tokenIn, address(this)) - reserves[tokenIn];

        return basicSwap(tokenIn, address(tokenOut), recipient, amountIn);
    }

    function swapWithContext(address tokenIn, address tokenOut,
                             bytes calldata context, address recipient,
                             bool unwrapBento, uint256 amountIn)
                            external override returns(uint256 finalAmountOut) {
        // TODO: add call to another contract
        return basicSwap(address(tokenIn), address(tokenOut), recipient,amountIn);
    }

    function basicSwap(address tokenIn, address tokenOut, address recipient,
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
        liquidity =  bento.balanceOf(address(token0),address(this)) - reserves[address(token0)];
        liquidity +=  bento.balanceOf(address(token1),address(this)) - reserves[address(token1)];
        liquidity +=  bento.balanceOf(address(token2),address(this)) - reserves[address(token2)];
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

        bento.transfer(address(tokenOut), address(this), to, amount);

        update(address(tokenOut));
    }

    function update(address token) internal {
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
    
    
    function getReserveOfToken(address token) public returns (uint256) {
        return reserves[token];

    }

    function getSplitValue(uint liquidity) private returns(uint256) {
        return liquidity /  NUM_TOKENS; 
        
    }

    function poolType() external pure override returns (uint256) {
        return 1;
    }

    function assets(uint256 index) external view override returns (address){
        if (index == 0 )
            return address(token0);
        else if (index == 1)
            return address(token1);
        else if (index == 2)
            return address(token2);
        require(false);
        return address(0);
            

    }

    function assetsCount() external view override returns (uint256) {
        return NUM_TOKENS;
    }
    
    
}
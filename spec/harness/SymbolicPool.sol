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
    // There is a set of tokens this pool supports
    IERC20[] public tokens;
    // the amount of holding the pool has for each token[i]
    mapping(IERC20 => uint256) public reserves; 
    // a symbolic representation of fixed conversion ratio between each two tokens
    mapping (IERC20 => mapping (IERC20 => uint256)) public rates; 
    
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
        update();
    }

    function getOptimalLiquidityInAmounts(liquidityInput[] calldata liquidityInputs) 
            external override returns(liquidityAmount[] memory liquidityOptimal) { }

    // a basic one to one mapping
    function mint(address to) external override returns(uint256 liquidity) {
        liquidity = getBalanceOfToken(0) - getReserveOfToken(0);
        liquidity += getBalanceOfToken(1) - getReserveOfToken(1);
        liquidity += getBalanceOfToken(2) - getReserveOfToken(2);
        _mint(to, liquidity);
        update(); 
    }

    // returns amount of shares in bentobox
    // TODO: not using unwrapBento ask Nurit
    function burn(address to, bool unwrapBento) 
            external override returns (liquidityAmount[] memory withdrawnAmounts) {
        // how much liquidity passed to the pool for burning
        uint256 liquidity = balanceOf[address(this)];
        
        _burn(address(this), liquidity);
        
        uint256 split = getSplitValue(liquidity); 
        
        withdrawnAmounts = new liquidityAmount[](tokens.length);

        if ( tokens.length > 0) {
            bento.transfer(tokens[0], address(this), to, split);
            withdrawnAmounts[0] = liquidityAmount({token: address(tokens[0]), amount: split});
        }

        if ( tokens.length > 1) {
            bento.transfer(tokens[1], address(this), to, split);
            withdrawnAmounts[1] = liquidityAmount({token: address(tokens[1]), amount: split});
        }

        if ( tokens.length > 2) {
            bento.transfer(tokens[2], address(this), to, split);
            withdrawnAmounts[2] = liquidityAmount({token: address(tokens[2]), amount: split});
        } 

        update();
    }

    function burnLiquiditySingle(address tokenOut, address to, bool unwrapBento)
            external override returns (uint256 amount) {
        uint256 amount = balanceOf[address(this)];

        _burn(address(this), amount);

        bento.transfer(IERC20(tokenOut), address(this), to, amount);

        update();
    }

    function update() internal {
        setReserveOfToken(0);
        setReserveOfToken(1);
        setReserveOfToken(2);
    }

    function tokensLength() public returns (uint256) {
        return tokens.length;
    }

    function isBalanced() public returns (bool) {
        return getBalanceOfToken(0) == getReserveOfToken(0) &&
               getBalanceOfToken(1) == getReserveOfToken(1) &&
               getBalanceOfToken(2) == getReserveOfToken(2);
    }
    
    function hasToken(address token) public returns (bool) {
        return  getToken(0) == token ||
                getToken(1) == token ||
                getToken(2) == token;
    }
    
    // function to avoid loops
    function getBalanceOfToken(uint i) public view returns (uint256) {
        if (tokens.length > i)
            return bento.balanceOf(IERC20(tokens[i]), address(this));

        return 0;
    }

    function getReserveOfToken(uint i) public returns (uint256) {
        if (tokens.length > i)
            return reserves[tokens[i]];

        return 0;
    }

    function setReserveOfToken(uint i) private returns (uint256) {
        if ( tokens.length > i)
            reserves[tokens[i]] = bento.balanceOf(IERC20(tokens[i]),address(this));
    } 

    function getToken(uint i) public returns (address) {
         if (tokens.length > i)
            return address(tokens[i]);
    }

    function getSplitValue(uint liquidity) private returns(uint256) {
        if (tokens.length == 1)
            return liquidity;
        if (tokens.length == 2)
            return liquidity / 2;
        if (tokens.length == 3)
            return liquidity / 3;
    }
}
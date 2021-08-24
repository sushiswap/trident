pragma solidity ^0.8.2;

import "../../contracts/pool/HybridPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HybridPoolHarness is HybridPool {
    uint256 public MAX_FEE_MINUS_SWAP_FEE;

    // constructor ///////////////
    constructor(bytes memory _deployData, address _masterDeployer)
            HybridPool(_deployData, _masterDeployer) {
        (address tokenA, address tokenB, uint256 _swapFee, bool _twapSupport) = 
                    abi.decode(_deployData, (address, address, uint256, bool));
        
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee; // TODO: check this with Nurit
    }

    // getters ///////////////////
    function tokenBalanceOf(IERC20 token, address user)
            public view returns (uint256 balance) {
        return token.balanceOf(user);
    }

    // wrappers //////////////////
    function mintWrapper(address to) public returns (uint256 liquidity) {
        bytes memory data = abi.encode(to);
        
        return super.mint(data);
    }

    function burnWrapper(address to, bool unwrapBento) 
            public returns (uint256 liquidity0_, uint256 liquidity1_) {
        bytes memory data = abi.encode(to, unwrapBento);

        IPool.TokenAmount[] memory withdrawnAmounts = super.burn(data);

        return (withdrawnAmounts[0].amount, withdrawnAmounts[1].amount);
    }

    function burnSingleWrapper(address tokenOut, address to, bool unwrapBento)
            public returns (uint256 amount) {
        bytes memory data = abi.encode(tokenOut, to, unwrapBento);
        
        return super.burnSingle(data);
    }

    // swapWrapper
    function swapWrapper(address tokenIn, address recipient, bool unwrapBento)
            public returns (uint256 amountOut) {
        bytes memory data = abi.encode(tokenIn, recipient, unwrapBento);
        
        return super.swap(data);
    }

    function flashSwapWrapper(address tokenIn, address recipient, bool unwrapBento,
                              uint256 amountIn, bytes memory context)
            public returns (uint256 amountOut) {
        // TODO: would be applied for all rules
        // require(recipient != address(this), "recepient is current contract");
        // require(recipient != token0, "recepient is token0");
        // require(recipient != token1, "recepient is token1");

        // require(tokenIn == token0, "wrong token");
        // require(tokenOut == token1, "wrong token");

        bytes memory data = abi.encode(tokenIn, recipient,  unwrapBento, amountIn, context);

        return super.flashSwap(data);
    }

    function getAmountOutWrapper(address tokenIn, uint256 amountIn) 
                public view returns (uint256 finalAmountOut) { 
        bytes memory data = abi.encode(tokenIn, amountIn);
        
        return super.getAmountOut(data);
    }

    // overrides /////////////////
    // WARNING: Be careful of interlocking "lock" modifier
    // if adding to the overrided code blocks
    function mint(bytes memory data) 
            public override lock returns (uint256 liquidity) { }

    function burn(bytes memory data)
            public override lock returns (IPool.TokenAmount[] memory withdrawnAmounts) { }

    function burnSingle(bytes memory data) 
            public override lock returns (uint256 amount) { }

    function swap(bytes memory data) 
            public override lock returns (uint256 amountOut) { }

    function flashSwap(bytes memory data)
            public override lock returns (uint256 amountOut) { }

    function getAmountOut(bytes memory data) 
            public view override returns (uint256 finalAmountOut) { }
}
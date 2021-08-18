pragma solidity ^0.8.2;
pragma abicoder v2;

import "../../contracts/TridentRouter.sol";
import "../../contracts/interfaces/IBentoBoxMinimal.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";



 interface Receiver {
        function sendTo() external payable returns (bool);
    } 

contract TridentRouterHarness is TridentRouter {
    IERC20 public tokenA;

    constructor(IBentoBoxMinimal _bento, address _wETH)
        TridentRouter(_bento, _wETH) public { }

    

 
    function callExactInputSingle(address tokenIn, 
        address tokenOut,
        address pool,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        uint256 amountOutMinimum)
        public
        virtual
        payable
        returns (uint256 amount)
    {
        bytes memory data = abi.encode(tokenIn, recipient, unwrapBento);
        ExactInputSingleParams memory exactInputSingleParams;
        exactInputSingleParams = ExactInputSingleParams({amountIn:amountIn,amountOutMinimum:amountOutMinimum, pool:pool, tokenIn:tokenIn, data: data});
        return super.exactInputSingle(exactInputSingleParams);
    }

    function exactInputSingle(ExactInputSingleParams memory params)
        public
        override
        payable
        returns (uint256 amountOut)
    { }


 /*  todo - try to put back
    function callExactInput(address tokenIn1, address pool1, address tokenIn2, address pool2,
        address tokenOut,
        address recipient,
        bool unwrapBento,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum)
        public
        virtual
        payable
        returns (uint256 amount)
    { }
    
        Path[] memory paths = new Path[](2);
        paths[0] = Path({tokenIn : tokenIn1, pool: pool1});
        paths[1] = Path({tokenIn : tokenIn2, pool: pool2});
        ExactInputParams memory exactInputParams = ExactInputParams({
                path : paths, 
                tokenOut : tokenOut, 
                recipient: recipient,
                unwrapBento : unwrapBento,
                deadline : deadline,
                amountIn : amountIn,
                amountOutMinimum : amountOutMinimum });
        return super.exactInput(exactInputParams);
    } */

    function exactInput(ExactInputParams memory params)
        public
        override
        payable
        returns (uint256 amount)
    { }

    function callExactInputSingleWithNativeToken(address tokenIn, 
        address tokenOut,
        address pool,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        uint256 amountOutMinimum)
        public
        virtual
        payable
        returns (uint256 amountOut)
    {
        bytes memory data = abi.encode(tokenIn, recipient, unwrapBento);
        ExactInputSingleParams memory exactInputSingleParams;
        exactInputSingleParams = ExactInputSingleParams({amountIn:amountIn, amountOutMinimum:amountOutMinimum, pool:pool, tokenIn:tokenIn, data: data});
        return super.exactInputSingleWithNativeToken(exactInputSingleParams);
    }

    function exactInputSingleWithNativeToken(ExactInputSingleParams memory params)
        public
        override
        payable
        returns (uint256 amountOut)
    { }

    //todo - add call function

    function exactInputWithNativeToken(ExactInputParams memory params)
        public
        override
        payable
        returns (uint256 amount)
    { }
    
    function complexPath(ComplexPathParams memory params) public override payable 
    { }

    function callAddLiquidity(address tokenIn1, uint256 amount1, bool native1,
                        address tokenIn2, uint256 amount2, bool native2, 
                        address pool,  address to, uint256 minliquidity) public returns (uint256) {
        TokenInput[] memory tokenInput = new TokenInput[](2);
        tokenInput[0] = TokenInput({token: tokenIn1, native : native1 , amount : amount1 });
        tokenInput[1] = TokenInput({token: tokenIn2, native : native2 , amount : amount2 });
        bytes memory data = abi.encode(to);
        return super.addLiquidity(tokenInput, pool, minliquidity, data);
    }

    function addLiquidity(
         TokenInput[] memory tokenInput,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) public  override returns (uint256 liquidity)  { }

    //todo - add call

    function burnLiquidity(
        address pool,
        uint256 liquidity,
        bytes calldata data,
        IPool.TokenAmount[] memory minWithdrawals
    ) public override { }

    function callBurnLiquiditySingle(
        address pool,
        uint256 liquidity,
        address tokenOut,
        address to,
        bool unwrapBento,
        uint256 minWithdrawal
    ) external  {
        bytes memory data = abi.encode(tokenOut, to, unwrapBento);
        return super.burnLiquiditySingle(pool, liquidity, data, minWithdrawal);
    }


    function burnLiquiditySingle(
         address pool,
        uint256 liquidity,
        bytes memory data,
        uint256 minWithdrawal
    ) public  override { }

   

    function safeTransfer(
        address token,
        address recipient,
        uint256 amount
    ) internal override {
        IERC20(token).transfer(recipient, amount);
    }

    function safeTransferFrom(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) internal override {
       IERC20(token).transferFrom(from, recipient, amount);
    }


    function safeTransferETH(address recipient, uint256 amount) internal override virtual {
        Receiver(recipient).sendTo{value: amount}();
    }

     function batch(bytes[] calldata data) external payable override returns (bytes[] memory results) { }

    function tokenBalanceOf(address token, address user) public returns (uint256) {
        return IERC20(token).balanceOf(user);
    }

    function ethBalance(address user) public returns (uint256) {
        return user.balance;
    }

}

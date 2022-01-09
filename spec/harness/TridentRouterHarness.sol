pragma solidity ^0.8.2;
pragma abicoder v2;

import "../../contracts/TridentRouter.sol";
import "../../contracts/interfaces/IBentoBoxMinimal.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Receiver {
    function sendTo() external payable returns (bool);
}

contract TridentRouterHarness is TridentRouter {
    constructor(
        IBentoBoxMinimal _bento,
        IMasterDeployer _masterDeployer,
        address _wETH
    ) TridentRouter(_bento, _masterDeployer, _wETH) {}

    function callExactInputSingle(
        address tokenIn,
        address pool,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) public payable virtual returns (uint256 amount) {
        bytes memory data = abi.encode(tokenIn, recipient, unwrapBento);

        ExactInputSingleParams memory exactInputSingleParams;
        exactInputSingleParams = ExactInputSingleParams({amountIn: amountIn, amountOutMinimum: amountOutMinimum, pool: pool, tokenIn: tokenIn, data: data});

        return super.exactInputSingle(exactInputSingleParams);
    }

    function exactInputSingle(ExactInputSingleParams memory params) public payable override returns (uint256 amountOut) {}

    // TODO: timing out on sanity
    /*
    function callExactInput(
        address tokenIn1,
        address pool1,
        address tokenIn2,
        address pool2,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) public payable virtual returns (uint256 amount) {
        Path[] memory paths = new Path[](2);

        // TODO: connect the pools using require? (Nurit - not at the moment)
        // Like pool1: tokenIn1, TokenOut1
        //      pool2: TokenIn2 (TokenOut1), _
        bytes memory data1 = abi.encode(tokenIn1, pool2, unwrapBento);
        bytes memory data2 = abi.encode(tokenIn2, recipient, unwrapBento);

        paths[0] = Path({pool: pool1, data: data1});
        paths[1] = Path({pool: pool2, data: data2});

        ExactInputParams memory exactInputParams = ExactInputParams({tokenIn: tokenIn1, amountIn: amountIn, amountOutMinimum: amountOutMinimum, path: paths});

        return super.exactInput(exactInputParams);
    }
*/
    function exactInput(ExactInputParams memory params) public payable override returns (uint256 amount) {}

    // TODO: exactInputLazy
    // TODO: CompilerError: Stack too deep, try removing local variables.
    // Shelly: --solc_args '["--optimize"]' \
    // This puts our analysis at a greater risk for failing, so you’d need to be
    // aware of that and check statsdata.json after the first run on a contract using this
    // function callExactInputLazy(
    //     address tokenIn1,
    //     address pool1,
    //     address tokenIn2,
    //     address pool2,
    //     address recipient,
    //     bool unwrapBento,
    //     uint256 amountIn,
    //     uint256 amountOutMinimum,
    //     address tridentCalleeToken1,
    //     address tridentCalleeFrom1,
    //     address tridentCalleeRecipient1,
    //     uint256 tridentCalleeShares1,
    //     address tridentCalleeToken2,
    //     address tridentCalleeFrom2,
    //     address tridentCalleeRecipient2,
    //     uint256 tridentCalleeShares2)
    //     public
    //     virtual
    //     payable
    //     returns (uint256 amount) {
    //     Path[] memory paths = new Path[](2);

    //     // TODO: if we are dealing with callbacks, need to link or do whatever is needed.
    //     // The callbacks defined in TridentRouter are useful to get the input tokens
    //     // from the user.
    //     bytes memory context1 = abi.encode(tridentCalleeToken1, tridentCalleeFrom1,
    //                                        tridentCalleeRecipient1, tridentCalleeShares1);
    //     bytes memory context2 = abi.encode(tridentCalleeToken2, tridentCalleeFrom2,
    //                                        tridentCalleeRecipient2, tridentCalleeShares2);

    //     // TODO: connect the pools using require? (Nurit - not at the moment)
    //     // Like pool1: tokenIn1, TokenOut1
    //     //      pool2: TokenIn2 (TokenOut1), _
    //     bytes memory data1 = abi.encode(tokenIn1, pool2, unwrapBento, amountIn, context1);
    //     bytes memory data2 = abi.encode(tokenIn2, recipient, unwrapBento, amountIn, context2); // TODO: amountIn needs to be the amountOut from previous flashSwap

    //     paths[0] = Path({ pool: pool1, data: data1 });
    //     paths[1] = Path({ pool: pool2, data: data2 });

    //     return super.exactInputLazy(amountOutMinimum, paths);
    // }

    function exactInputLazy(uint256 amountOutMinimum, Path[] memory path) public payable override returns (uint256 amount) {}

    function callExactInputSingleWithNativeToken(
        address tokenIn,
        address pool,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) public payable virtual returns (uint256 amountOut) {
        bytes memory data = abi.encode(tokenIn, recipient, unwrapBento);

        ExactInputSingleParams memory exactInputSingleParams;
        exactInputSingleParams = ExactInputSingleParams({amountIn: amountIn, amountOutMinimum: amountOutMinimum, pool: pool, tokenIn: tokenIn, data: data});

        return super.exactInputSingleWithNativeToken(exactInputSingleParams);
    }

    function exactInputSingleWithNativeToken(ExactInputSingleParams memory params) public payable override returns (uint256 amountOut) {}

    // TODO: timing out on sanity
    
    function callExactInputWithNativeToken(
        address tokenIn1,
        address pool1,
        address tokenIn2,
        address pool2,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) public payable virtual returns (uint256 amount) {
     /*   Path[] memory paths = new Path[](2);

        // TODO: connect the pools using require? (Nurit - not at the moment)
        // Like pool1: tokenIn1, TokenOut1
        //      pool2: TokenIn2 (TokenOut1), _
        bytes memory data1 = abi.encode(tokenIn1, pool2, unwrapBento);
        bytes memory data2 = abi.encode(tokenIn2, recipient, unwrapBento);

        paths[0] = Path({pool: pool1, data: data1});
        paths[1] = Path({pool: pool2, data: data2});

        ExactInputParams memory exactInputParams = ExactInputParams({tokenIn: tokenIn1, amountIn: amountIn, amountOutMinimum: amountOutMinimum, path: paths});

        return super.exactInputWithNativeToken(exactInputParams);
        */
    }

    function exactInputWithNativeToken(ExactInputParams memory params) public payable override returns (uint256 amount) {}

    // TODO: need to add a call function for complexPath
    // Nurit - very complex, last thing to do if we have time, otherwise
    // state that this function was out of scope same for callExactInputLazy
    function complexPath(ComplexPathParams memory params) public payable override {}

    function callAddLiquidity(
        address tokenIn1,
        uint256 amount1,
        bool native1,
        address tokenIn2,
        uint256 amount2,
        bool native2,
        address pool,
        address to,
        uint256 minliquidity
    ) public payable returns (uint256) {
        TokenInput[] memory tokenInput = new TokenInput[](2);

        tokenInput[0] = TokenInput({token: tokenIn1, native: native1, amount: amount1});
        tokenInput[1] = TokenInput({token: tokenIn2, native: native2, amount: amount2});

        bytes memory data = abi.encode(to);

        return super.addLiquidity(tokenInput, pool, minliquidity, data);
    }

    function addLiquidity(
        TokenInput[] memory tokenInput,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) public payable override returns (uint256 liquidity) {}

    function callBurnLiquidity(
        address pool,
        uint256 liquidity,
        address to,
        bool unwrapBento,
        address token1,
        address token2,
        uint256 minToken1,
        uint256 minToken2
    ) external {
/*        IPool.TokenAmount[] memory minWithdrawals = new IPool.TokenAmount[](2);

        minWithdrawals[0] = IPool.TokenAmount({token: token1, amount: minToken1});
        minWithdrawals[1] = IPool.TokenAmount({token: token2, amount: minToken2});

        bytes memory data = abi.encode(to, unwrapBento);

        return super.burnLiquidity(pool, liquidity, data, minWithdrawals); */
    }

    function burnLiquidity(
        address pool,
        uint256 liquidity,
        bytes calldata data,
        IPool.TokenAmount[] memory minWithdrawals
    ) public override {}

    function callBurnLiquiditySingle(
        address pool,
        uint256 liquidity,
        address tokenOut,
        address to,
        bool unwrapBento,
        uint256 minWithdrawal
    ) external {
        bytes memory data = abi.encode(tokenOut, to, unwrapBento);

        return super.burnLiquiditySingle(pool, liquidity, data, minWithdrawal);
    }

    function burnLiquiditySingle(
        address pool,
        uint256 liquidity,
        bytes memory data,
        uint256 minWithdrawal
    ) public override {}

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

    function safeTransferETH(address recipient, uint256 amount) internal virtual override {
        Receiver(recipient).sendTo{value: amount}();
    }

    // TODO: do we need to stimulate this, so that we don't commit the same
    // error as we did in DutchAuction
    // Nurit - we should comment that this is an unsound simplification however,
    // the code does not trust the msg.value. Instead the current balance is checked.
    function batch(bytes[] calldata data) external payable override returns (bytes[] memory results) {}

    function tokenBalanceOf(address token, address user) public view returns (uint256) {
        return IERC20(token).balanceOf(user);
    }

    function ethBalance(address user) public view returns (uint256) {
        return user.balance;
    }
}

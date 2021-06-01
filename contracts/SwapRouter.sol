// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.2;
pragma abicoder v2;

import "./interfaces/ISwapRouter.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IBentoBox.sol";

import "./base/Multicall.sol";
import "./base/SelfPermit.sol";
import "./deployer/MasterDeployer.sol";

import "./libraries/TransferHelper.sol";

contract SwapRouter is
    ISwapRouter,
    Multicall,
    SelfPermit
{

    address public immutable WETH9;
    address public immutable masterDeployer;
    address public immutable bento;

    constructor(address _WETH9, address _masterDeployer, address _bento) {
        WETH9 = _WETH9;
        masterDeployer = _masterDeployer;
        bento = _bento;
    }

    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "Transaction too old");
        _;
    }

    receive() external payable {
        require(msg.sender == WETH9, "Not WETH9");
    }

    /// @dev Performs a single exact input swap
    function exactInputInternal(
        address tokenIn,
        address tokenOut,
        address pool,
        bytes memory context,
        address recipient,
        address payer,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        // Pay optimisticly.
        pay(tokenIn, payer, pool, amountIn);

        amountOut = exactInputInternalWithoutPay(tokenIn, tokenOut, pool, context, recipient, payer, amountIn);
    }

    /// @dev Performs a single exact input swap
    function exactInputInternalWithoutPay(
        address tokenIn,
        address tokenOut,
        address pool,
        bytes memory context,
        address recipient,
        address payer,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        require(MasterDeployer(masterDeployer).pool(pool), "Not official pool");

        amountOut =
            IPool(pool).swap(
                tokenIn,
                tokenOut,
                context,
                recipient,
                true,
                amountIn
            );
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        amountOut = exactInputInternal(
            params.tokenIn,
            params.tokenOut,
            params.pool,
            params.context,
            params.recipient,
            msg.sender,
            params.amountIn

        );
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function exactInput(ExactInputParams memory params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amount)
    {
        amount = params.amountIn;
        address payer = msg.sender;

        for (uint256 i; i < params.path.length; i++) {
            bool isLastPool = params.path.length == i + 1;

            // the outputs of prior swaps become the inputs to subsequent ones
            amount = exactInputInternal(
                params.path[i].inputToken,
                isLastPool ? params.path[i + 1].inputToken : params.tokenOut,
                params.path[i].pool,
                params.path[i].context,
                isLastPool ? params.recipient : address(this),
                payer,
                amount
            );

            payer = address(this);
        }

        require(amount >= params.amountOutMinimum, "Too little received");
    }

    function exactInputFirstHopWithNativeTokens(
        address tokenIn,
        address tokenOut,
        address pool,
        bytes memory context,
        address recipient,
        address payer,
        uint256 amountIn,
        bool nativeInput
    ) private returns (uint256 amountOut) {
        if (nativeInput) {
            IBentoBoxV1(bento).deposit(IERC20(tokenIn), payer, address(this), amountIn, 0);
            amountOut = exactInputInternalWithoutPay(
                tokenIn,
                tokenOut,
                pool,
                context,
                recipient,
                msg.sender,
                amountIn
            );
        } else {
            amountOut = exactInputInternal(
                tokenIn,
                tokenOut,
                pool,
                context,
                recipient,
                msg.sender,
                amountIn
            );
        }
    }

    function exactInputSingleWithNativeTokens(ExactInputSingleParams calldata params, bool nativeInput, bool nativeOutput)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        address recipient = nativeOutput ? address(this) : params.recipient;

        amountOut = exactInputFirstHopWithNativeTokens(
            params.tokenIn,
            params.tokenOut,
            params.pool,
            params.context,
            recipient,
            msg.sender,
            params.amountIn,
            nativeInput
        );

        require(amountOut >= params.amountOutMinimum, "Too little received");

        if (nativeOutput) {
            IBentoBoxV1(bento).withdraw(IERC20(params.tokenOut), address(this), params.recipient, amountOut, 0);
        }
    }

    function exactInputWithNativeTokens(ExactInputParams memory params, bool nativeInput, bool nativeOutput)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amount)
    {
        address payer = msg.sender;

        amount = exactInputFirstHopWithNativeTokens(
            params.path[0].inputToken,
            params.path.length > 1 ? params.path[1].inputToken : params.tokenOut,
            params.path[0].pool,
            params.path[0].context,
            params.path.length > 1 || nativeOutput ? address(this) : params.recipient,
            msg.sender,
            params.amountIn,
            nativeInput
        );

        for (uint256 i = 1; i < params.path.length; i++) {
            bool isLastPool = params.path.length == i + 1;

            // the outputs of prior swaps become the inputs to subsequent ones
            amount = exactInputInternal(
                params.path[i].inputToken,
                isLastPool ? params.path[i + 1].inputToken : params.tokenOut,
                params.path[i].pool,
                params.path[i].context,
                isLastPool && !nativeOutput ? params.recipient : address(this),
                payer,
                amount
            );

            payer = address(this);
        }

        require(amount >= params.amountOutMinimum, "Too little received");
        if (nativeOutput) {
            IBentoBoxV1(bento).withdraw(IERC20(params.tokenOut), address(this), params.recipient, amount, 0);
        }
    }

    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable {
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        require(balanceToken >= amountMinimum, "Insufficient token");

        if (balanceToken > 0) {
            TransferHelper.safeTransfer(token, recipient, balanceToken);
        }
    }

    function refundETH() external payable {
        if (address(this).balance > 0) TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // Deposit eth into recipient bentobox
            IBentoBoxV1(bento).deposit{value: value}(IERC20(address(0)), address(this), recipient, value, 0);
        } else {
            // Process payment via bentobox
            IBentoBoxV1(bento).transfer(IERC20(token), payer, recipient, IBentoBoxV1(bento).toShare(IERC20(token), value, false));
        }
    }
}

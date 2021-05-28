// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.2;
pragma abicoder v2;

import "./interfaces/ISwapRouter.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IPool.sol";

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

    constructor(address _WETH9, address _masterDeployer) {
        WETH9 = _WETH9;
        masterDeployer = _masterDeployer;
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
        require(MasterDeployer(masterDeployer).pool(pool), "Not official pool");

        // Pay optimisticly.
        pay(tokenIn, payer, pool, amountIn);

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

    function unwrapWETH9(uint256 amountMinimum, address recipient) external payable {
        uint256 balanceWETH9 = IWETH(WETH9).balanceOf(address(this));
        require(balanceWETH9 >= amountMinimum, "Insufficient WETH9");

        if (balanceWETH9 > 0) {
            IWETH(WETH9).withdraw(balanceWETH9);
            TransferHelper.safeTransferETH(recipient, balanceWETH9);
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
            // pay with WETH9
            IWETH(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            IWETH(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}

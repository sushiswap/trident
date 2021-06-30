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

import "hardhat/console.sol";

contract SwapRouter is ISwapRouter, Multicall, SelfPermit {
    address public immutable WETH;
    address public immutable masterDeployer;
    address public immutable bento;

    constructor(
        address _WETH,
        address _masterDeployer,
        address _bento
    ) {
        WETH = _WETH;
        masterDeployer = _masterDeployer;
        bento = _bento;
        IBentoBoxV1(_bento).registerProtocol();
    }

    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "Transaction too old");
        _;
    }

    receive() external payable {
        require(msg.sender == WETH, "Not WETH");
    }

    /// @dev Performs a single exact input swap
    function exactInputInternal(
        address tokenIn,
        address tokenOut,
        address pool,
        address recipient,
        address payer,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Pay optimisticly.
        pay(tokenIn, payer, pool, amountIn);

        amountOut = exactInputInternalWithoutPay(tokenIn, tokenOut, pool, recipient, amountIn);
    }

    /// @dev Performs a single exact input swap
    function exactInputInternalWithoutPay(
        address tokenIn,
        address tokenOut,
        address pool,
        address recipient,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        require(MasterDeployer(masterDeployer).pool(pool), "Not official pool");
        amountOut = IPool(pool).swapExactIn(tokenIn, tokenOut, recipient, amountIn);
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
        if (token == WETH && address(this).balance >= value) {
            // Deposit eth into recipient bentobox
            IBentoBoxV1(bento).deposit{value: value}(IERC20(address(0)), address(this), recipient, value, 0);
        } else {
            // Process payment via bentobox
            IBentoBoxV1(bento).transfer(IERC20(token), payer, recipient, IBentoBoxV1(bento).toShare(IERC20(token), value, false));
        }
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
                params.path[i].tokenIn,
                isLastPool ? params.tokenOut : params.path[i + 1].tokenIn,
                params.path[i].pool,
                isLastPool ? params.recipient : address(this),
                payer,
                amount
            );

            payer = address(this);
        }

        require(amount >= params.amountOutMinimum, "Too little received");
    }

    function complexPath(ComplexPathParams memory params)
        external
        payable
        checkDeadline(params.deadline)
    {
        for (uint256 i; i < params.initialPath.length; i++) {
            if (!params.initialPath[i].preFunded) {
                pay(params.initialPath[i].tokenIn, msg.sender, params.initialPath[i].pool, params.initialPath[i].amountIn);
            }
            IPool(params.initialPath[i].pool).swapWithContext(
                params.initialPath[i].tokenIn,
                params.initialPath[i].tokenOut,
                params.initialPath[i].context,
                address(this),
                params.initialPath[i].amountIn,
                0
            );
        }

        for (uint256 i; i < params.percentagePath.length; i++) {
            uint256 balanceShares = IBentoBoxV1(bento).balanceOf(IERC20(params.percentagePath[i].tokenIn), address(this));
            uint256 balanceAmount = IBentoBoxV1(bento).toAmount(IERC20(params.percentagePath[i].tokenIn), balanceShares, false);
            uint256 transferAmount = (balanceAmount * params.percentagePath[i].balancePercentage) / uint256(10)**6;
            pay(params.percentagePath[i].tokenIn, address(this), params.percentagePath[i].pool, transferAmount);
            IPool(params.percentagePath[i].pool).swapWithContext(
                params.percentagePath[i].tokenIn,
                params.percentagePath[i].tokenOut,
                params.percentagePath[i].context,
                address(this),
                transferAmount,
                0
            );
        }

        for (uint256 i; i < params.output.length; i++) {
            uint256 balanceShares = IBentoBoxV1(bento).balanceOf(IERC20(params.output[i].token), address(this));
            uint256 balanceAmount = IBentoBoxV1(bento).toAmount(IERC20(params.output[i].token), balanceShares, false);
            require(balanceAmount >= params.output[i].minAmount, "Too little received");
            pay(params.output[i].token, address(this), params.output[i].to, balanceShares);
        }
    }

    function exactInputSingleWithPreFunding(ExactInputSingleParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        amountOut = exactInputInternalWithoutPay(
            params.tokenIn,
            params.tokenOut,
            params.pool,
            params.recipient,
            params.amountIn
        );

        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function exactInputWithPreFunding(ExactInputParams memory params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amount)
    {
        address payer = msg.sender;

        amount = exactInputInternalWithoutPay(
            params.path[0].tokenIn,
            params.path.length > 1 ? params.path[1].tokenIn : params.tokenOut,
            params.path[0].pool,
            params.path.length > 1 ? address(this) : params.recipient,
            params.amountIn
        );

        for (uint256 i = 1; i < params.path.length; i++) {
            bool isLastPool = params.path.length == i + 1;

            // the outputs of prior swaps become the inputs to subsequent ones
            amount = exactInputInternal(
                params.path[i].tokenIn,
                isLastPool ? params.path[i + 1].tokenIn : params.tokenOut,
                params.path[i].pool,
                isLastPool ? params.recipient : address(this),
                payer,
                amount
            );

            payer = address(this);
        }

        require(amount >= params.amountOutMinimum, "Too little received");
    }

    function addLiquidityUnbalanced(
        IPool.liquidityInputOptimal[] calldata liquidityInput,
        address pool,
        address to,
        uint256 deadline,
        uint256 minLiquidity
    ) external checkDeadline(deadline) returns (uint256 liquidity) {
        for (uint256 i; i < liquidityInput.length; i++) {
            if (liquidityInput[i].native) {
                IBentoBoxV1(bento).deposit(IERC20(liquidityInput[i].token), msg.sender, pool, liquidityInput[i].amount, 0);
            } else {
                uint256 shares = IBentoBoxV1(bento).toShare(IERC20(liquidityInput[i].token), liquidityInput[i].amount, false);
                IBentoBoxV1(bento).transfer(IERC20(liquidityInput[i].token), msg.sender, pool, shares);
            }
        }
        liquidity = IPool(pool).mint(to);
        require(liquidity >= minLiquidity, "Not enough liquidity minted");
    }

    function addLiquidityBalanced(
        IPool.liquidityInput[] calldata liquidityInput,
        address pool,
        address to,
        uint256 deadline
    ) external checkDeadline(deadline) returns (IPool.liquidityAmount[] memory liquidityOptimal, uint256 liquidity) {
        liquidityOptimal = IPool(pool).getOptimalLiquidityInAmounts(liquidityInput);
        for (uint256 i; i < liquidityOptimal.length; i++) {
            require(liquidityOptimal[i].amount >= liquidityInput[i].amountMin, "Amount not Optimal");
            if (liquidityInput[i].native) {
                IBentoBoxV1(bento).deposit(IERC20(liquidityOptimal[i].token), msg.sender, pool, liquidityOptimal[i].amount, 0);
            } else {
                uint256 shares = IBentoBoxV1(bento).toShare(IERC20(liquidityOptimal[i].token), liquidityOptimal[i].amount, false);
                IBentoBoxV1(bento).transfer(IERC20(liquidityOptimal[i].token), msg.sender, pool, shares);
            }
        }
        liquidity = IPool(pool).mint(to);
    }

    function depositToBentoBox(
        address token,
        uint256 amount,
        address recipient
    ) external payable {
        IBentoBoxV1(bento).deposit(IERC20(token), msg.sender, recipient, amount, 0);
    }

    function sweepBentoBoxToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable {
        uint256 balanceShares = IBentoBoxV1(bento).balanceOf(IERC20(token), address(this));
        require(IBentoBoxV1(bento).toAmount(IERC20(token), balanceShares, false) >= amountMinimum, "Insufficient token");

        if (balanceShares > 0) {
            IBentoBoxV1(bento).withdraw(IERC20(token), address(this), recipient, 0, balanceShares);
        }
    }

    function sweepNativeToken(
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

    function unwrapWETH(uint256 amountMinimum, address recipient) external payable {
        uint256 balanceWETH = IWETH(WETH).balanceOf(address(this));
        require(balanceWETH >= amountMinimum, "Insufficient WETH");

        if (balanceWETH > 0) {
            IWETH(WETH).withdraw(balanceWETH);
            TransferHelper.safeTransferETH(recipient, balanceWETH);
        }
    }
}

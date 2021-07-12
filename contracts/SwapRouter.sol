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

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        pay(params.tokenIn, msg.sender, params.pool, params.amountIn);
        amountOut = IPool(params.pool).swapExactIn(
            params.tokenIn,
            params.tokenOut,
            params.recipient,
            params.unwrapBento,
            params.amountIn
        );
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function exactInput(ExactInputParams memory params) external payable checkDeadline(params.deadline) returns (uint256 amount) {
        amount = params.amountIn;
        // Pay the first pool directly
        pay(params.path[0].tokenIn, msg.sender, params.path[0].pool, amount);
        return _preFundedExactInput(params);
    }

    function exactInputSingleWithNativeToken(ExactInputSingleParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        _depositToBentoBox(params.tokenIn, params.pool, params.amountIn);
        amountOut = IPool(params.pool).swapExactIn(
            params.tokenIn,
            params.tokenOut,
            params.recipient,
            params.unwrapBento,
            params.amountIn
        );
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function exactInputWithNativeToken(ExactInputParams memory params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amount)
    {
        amount = params.amountIn;
        _depositToBentoBox(params.path[0].tokenIn, params.path[0].pool, amount);
        return _preFundedExactInput(params);
    }

    function exactInputSingleWithContext(ExactInputSingleParamsWithContext calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        pay(params.tokenIn, msg.sender, params.pool, params.amountIn);
        amountOut = IPool(params.pool).swapWithContext(
            params.tokenIn,
            params.tokenOut,
            params.context,
            params.recipient,
            params.unwrapBento,
            params.amountIn,
            0
        );
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function exactInputWithContext(ExactInputParamsWithContext memory params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amount)
    {
        amount = params.amountIn;
        // Pay the first pool directly
        pay(params.path[0].tokenIn, msg.sender, params.path[0].pool, amount);
        return _preFundedExactInputWithContext(params);
    }

    function exactInputSingleWithNativeTokenAndContext(ExactInputSingleParamsWithContext calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        _depositToBentoBox(params.tokenIn, params.pool, params.amountIn);
        amountOut = IPool(params.pool).swapWithContext(
            params.tokenIn,
            params.tokenOut,
            params.context,
            params.recipient,
            params.unwrapBento,
            params.amountIn,
            0
        );
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function exactInputWithNativeTokenAndContext(ExactInputParamsWithContext memory params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amount)
    {
        amount = params.amountIn;
        _depositToBentoBox(params.path[0].tokenIn, params.path[0].pool, amount);
        return _preFundedExactInputWithContext(params);
    }

    function complexPath(ComplexPathParams memory params) external payable checkDeadline(params.deadline) {
        for (uint256 i; i < params.initialPath.length; i++) {
            if (!params.initialPath[i].preFunded) {
                pay(params.initialPath[i].tokenIn, msg.sender, params.initialPath[i].pool, params.initialPath[i].amountIn);
            }
            IPool(params.initialPath[i].pool).swapWithContext(
                params.initialPath[i].tokenIn,
                params.initialPath[i].tokenOut,
                params.initialPath[i].context,
                address(this),
                false,
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
                false,
                transferAmount,
                0
            );
        }

        for (uint256 i; i < params.output.length; i++) {
            uint256 balanceShares = IBentoBoxV1(bento).balanceOf(IERC20(params.output[i].token), address(this));
            uint256 balanceAmount = IBentoBoxV1(bento).toAmount(IERC20(params.output[i].token), balanceShares, false);
            require(balanceAmount >= params.output[i].minAmount, "Too little received");
            if (params.output[i].unwrapBento) {
                IBentoBoxV1(bento).withdraw(IERC20(params.output[i].token), address(this), params.output[i].to, 0, balanceShares);
            } else {
                pay(params.output[i].token, address(this), params.output[i].to, balanceShares);
            }
        }
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
                _depositToBentoBox(liquidityInput[i].token, pool, liquidityInput[i].amount);
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
                _depositToBentoBox(liquidityOptimal[i].token, pool, liquidityOptimal[i].amount);
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
        IBentoBoxV1(bento).deposit{value: address(this).balance}(IERC20(token), msg.sender, recipient, amount, 0);
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

    function _preFundedExactInput(ExactInputParams memory params) internal returns (uint256 amount) {
        amount = params.amountIn;

        for (uint256 i = 0; i < params.path.length - 1; i++) {
            amount = IPool(params.path[i].pool).swapExactIn(
                params.path[i].tokenIn,
                params.path[i + 1].tokenIn,
                params.path[i + 1].pool,
                false,
                amount
            );
        }

        // last hop
        amount = IPool(params.path[params.path.length - 1].pool).swapExactIn(
            params.path[params.path.length - 1].tokenIn,
            params.tokenOut,
            params.recipient,
            params.unwrapBento,
            amount
        );

        require(amount >= params.amountOutMinimum, "Too little received");
    }

    function _preFundedExactInputWithContext(ExactInputParamsWithContext memory params) internal returns (uint256 amount) {
        amount = params.amountIn;

        for (uint256 i; i < params.path.length; i++) {
            if (params.path.length == i + 1) {
                // last hop
                amount = IPool(params.path[i].pool).swapWithContext(
                    params.path[i].tokenIn,
                    params.tokenOut,
                    params.path[i].context,
                    params.recipient,
                    params.unwrapBento,
                    amount,
                    0
                );
            } else {
                amount = IPool(params.path[i].pool).swapWithContext(
                    params.path[i].tokenIn,
                    params.path[i + 1].tokenIn,
                    params.path[i].context,
                    params.path[i + 1].pool,
                    false,
                    amount,
                    0
                );
            }
        }

        require(amount >= params.amountOutMinimum, "Too little received");
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

    /// @param token The token to pay
    /// @param recipient The entity that will receive payment
    /// @param amount The amount to pay
    function _depositToBentoBox(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if ((token == WETH || token == address(0)) && address(this).balance >= amount) {
            // Deposit eth into recipient bentobox
            IBentoBoxV1(bento).deposit{value: amount}(IERC20(address(0)), address(this), recipient, amount, 0);
        } else {
            // Deposit ERC20 token to bentobox
            IBentoBoxV1(bento).deposit(IERC20(token), msg.sender, recipient, amount, 0);
        }
    }
}

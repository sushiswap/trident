// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.2;
pragma abicoder v2;

import "./interfaces/ISwapRouter.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IBentoBox.sol";
import "./interfaces/IFlashLoan.sol";

import "./base/Multicall.sol";
import "./base/SelfPermit.sol";

import "./libraries/TransferHelper.sol";

import "hardhat/console.sol";

contract SwapRouter is IFlashBorrower, ISwapRouter, Multicall, SelfPermit {
    address public immutable WETH;
    IBentoBoxV1 public immutable bento;

    constructor(address _WETH, IBentoBoxV1 _bento) {
        WETH = _WETH;
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
        amountOut = IPool(params.pool).swapWithoutContext(
            params.tokenIn,
            params.tokenOut,
            params.recipient,
            params.unwrapBento
        );
        amountOut = bento.toAmount(IERC20(params.tokenOut), amountOut, false);
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function exactInput(ExactInputParams memory params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amount)
    {
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
        amountOut = IPool(params.pool).swapWithoutContext(
            params.tokenIn,
            params.tokenOut,
            params.recipient,
            params.unwrapBento
        );
        amountOut = bento.toAmount(IERC20(params.tokenOut), amountOut, false);
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
        uint256 amountIn = bento.toShare(IERC20(params.tokenIn), params.amountIn, false);
        amountOut = IPool(params.pool).swapWithContext(
            params.tokenIn,
            params.tokenOut,
            params.context,
            params.recipient,
            params.unwrapBento,
            amountIn
        );
        amountOut = bento.toAmount(IERC20(params.tokenOut), amountOut, false);
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
        uint256 amountIn = bento.toShare(IERC20(params.tokenIn), params.amountIn, false);
        amountOut = IPool(params.pool).swapWithContext(
            params.tokenIn,
            params.tokenOut,
            params.context,
            params.recipient,
            params.unwrapBento,
            amountIn
        );
        amountOut = bento.toAmount(IERC20(params.tokenOut), amountOut, false);
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
                pay(
                    params.initialPath[i].tokenIn,
                    msg.sender,
                    params.initialPath[i].pool,
                    params.initialPath[i].amountIn
                );
            }
            uint256 amountIn = bento.toShare(
                IERC20(params.initialPath[i].tokenIn),
                params.initialPath[i].amountIn,
                false
            );
            IPool(params.initialPath[i].pool).swapWithContext(
                params.initialPath[i].tokenIn,
                params.initialPath[i].tokenOut,
                params.initialPath[i].context,
                address(this),
                false,
                amountIn
            );
        }

        for (uint256 i; i < params.percentagePath.length; i++) {
            uint256 balanceShares = bento.balanceOf(IERC20(params.percentagePath[i].tokenIn), address(this));
            uint256 transferShares = (balanceShares * params.percentagePath[i].balancePercentage) / uint256(10)**6;
            payInShares(params.percentagePath[i].tokenIn, address(this), params.percentagePath[i].pool, transferShares);
            IPool(params.percentagePath[i].pool).swapWithContext(
                params.percentagePath[i].tokenIn,
                params.percentagePath[i].tokenOut,
                params.percentagePath[i].context,
                address(this),
                false,
                transferShares
            );
        }

        for (uint256 i; i < params.output.length; i++) {
            uint256 balanceShares = bento.balanceOf(IERC20(params.output[i].token), address(this));
            uint256 balanceAmount = bento.toAmount(IERC20(params.output[i].token), balanceShares, false);
            require(balanceAmount >= params.output[i].minAmount, "Too little received");
            if (params.output[i].unwrapBento) {
                bento.withdraw(IERC20(params.output[i].token), address(this), params.output[i].to, 0, balanceShares);
            } else {
                payInShares(params.output[i].token, address(this), params.output[i].to, balanceShares);
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
                uint256 shares = bento.toShare(IERC20(liquidityInput[i].token), liquidityInput[i].amount, false);
                bento.transfer(IERC20(liquidityInput[i].token), msg.sender, pool, shares);
            }
        }
        liquidity = IPool(pool).mint(to);
        require(liquidity >= minLiquidity, "Not enough liquidity minted");
    }

    function addLiquidityBalanced(
        IPool.liquidityInput[] memory liquidityInput,
        address pool,
        address to,
        uint256 deadline
    ) external checkDeadline(deadline) returns (IPool.liquidityAmount[] memory liquidityOptimal, uint256 liquidity) {
        for (uint256 i; i < liquidityInput.length; i++) {
            liquidityInput[i].amountDesired = bento.toShare(
                IERC20(liquidityInput[i].token),
                liquidityInput[i].amountDesired,
                false
            );
        }
        liquidityOptimal = IPool(pool).getOptimalLiquidityInAmounts(liquidityInput);
        for (uint256 i; i < liquidityOptimal.length; i++) {
            uint256 underlyingAmount = bento.toAmount(
                IERC20(liquidityOptimal[i].token),
                liquidityOptimal[i].amount,
                false
            );
            require(underlyingAmount >= liquidityInput[i].amountMin, "Amount not Optimal");
            if (liquidityInput[i].native) {
                _depositSharesToBentoBox(liquidityOptimal[i].token, pool, liquidityOptimal[i].amount);
            } else {
                bento.transfer(IERC20(liquidityOptimal[i].token), msg.sender, pool, liquidityOptimal[i].amount);
            }
        }
        liquidity = IPool(pool).mint(to);
    }

    function burnLiquidity(
        address pool,
        address to,
        bool unwrapBento,
        uint256 deadline,
        uint256 liquidity,
        IPool.liquidityAmount[] memory minWithdrawals
    ) external checkDeadline(deadline) {
        require(IERC20(pool).transferFrom(msg.sender, pool, liquidity));
        IPool.liquidityAmount[] memory withdrawnLiquidity = IPool(pool).burn(to, unwrapBento);
        for (uint256 i; i < minWithdrawals.length; i++) {
            uint256 j;
            for (; j < withdrawnLiquidity.length; j++) {
                if (withdrawnLiquidity[j].token == minWithdrawals[i].token) {
                    uint256 underlyingAmount = bento.toAmount(
                        IERC20(withdrawnLiquidity[j].token),
                        withdrawnLiquidity[j].amount,
                        false
                    );
                    require(underlyingAmount >= minWithdrawals[i].amount, "Too little received");
                    break;
                }
            }
            // A token that is present in `minWithdrawals` is missing from `withdrawnLiquidity`.
            require(j < withdrawnLiquidity.length, "Incorrect token withdrawn");
        }
    }

    function burnLiquiditySingle(
        address pool,
        address tokenOut,
        address to,
        bool unwrapBento,
        uint256 deadline,
        uint256 liquidity,
        uint256 minWithdrawal
    ) external checkDeadline(deadline) {
        // Use liquidity = 0 for pre funding
        require(IERC20(pool).transferFrom(msg.sender, pool, liquidity));
        uint256 withdrawn = IPool(pool).burnLiquiditySingle(tokenOut, to, unwrapBento);
        withdrawn = bento.toAmount(IERC20(tokenOut), withdrawn, false);
        require(withdrawn >= minWithdrawal, "Too little received");
    }

    function depositToBentoBox(
        address token,
        uint256 amount,
        address recipient
    ) external payable {
        bento.deposit{value: address(this).balance}(IERC20(token), msg.sender, recipient, amount, 0);
    }

    function sweepBentoBoxToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable {
        uint256 balanceShares = bento.balanceOf(IERC20(token), address(this));
        require(bento.toAmount(IERC20(token), balanceShares, false) >= amountMinimum, "Insufficient token");

        if (balanceShares > 0) {
            bento.withdraw(IERC20(token), address(this), recipient, 0, balanceShares);
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
        amount = bento.toShare(IERC20(params.path[0].tokenIn), params.amountIn, false);
        uint256 lenMinusOne = params.path.length - 1;

        for (uint256 i; i < lenMinusOne; i++) {
            amount = IPool(params.path[i].pool).swapWithoutContext(
                params.path[i].tokenIn,
                params.path[i + 1].tokenIn,
                params.path[i + 1].pool,
                false
            );
        }

        // last hop
        amount = IPool(params.path[lenMinusOne].pool).swapWithoutContext(
            params.path[lenMinusOne].tokenIn,
            params.tokenOut,
            params.recipient,
            params.unwrapBento
        );

        amount = bento.toAmount(IERC20(params.path[lenMinusOne].tokenIn), amount, false);
        require(amount >= params.amountOutMinimum, "Too little received");
    }

    function _preFundedExactInputWithContext(ExactInputParamsWithContext memory params)
        internal
        returns (uint256 amount)
    {
        amount = bento.toShare(IERC20(params.path[0].tokenIn), params.amountIn, false);
        uint256 lenMinusOne = params.path.length - 1;

        for (uint256 i; i < lenMinusOne; i++) {
            amount = IPool(params.path[i].pool).swapWithContext(
                params.path[i].tokenIn,
                params.path[i + 1].tokenIn,
                params.path[i].context,
                params.path[i + 1].pool,
                false,
                amount
            );
        }

        amount = IPool(params.path[lenMinusOne].pool).swapWithContext(
            params.path[lenMinusOne].tokenIn,
            params.tokenOut,
            params.path[lenMinusOne].context,
            params.recipient,
            params.unwrapBento,
            amount
        );

        amount = bento.toAmount(IERC20(params.path[lenMinusOne].tokenIn), amount, false);
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
        if (token == address(0) || (token == WETH && address(this).balance >= value)) {
            // Deposit eth into recipient bentobox
            bento.deposit{value: value}(IERC20(address(0)), address(this), recipient, value, 0);
        } else {
            // Process payment via bentobox
            bento.transfer(IERC20(token), payer, recipient, bento.toShare(IERC20(token), value, false));
        }
    }

    function payInShares(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == address(0) || (token == WETH && address(this).balance >= value)) {
            // Deposit eth into recipient bentobox
            bento.deposit{value: value}(IERC20(address(0)), address(this), recipient, 0, value);
        } else {
            // Process payment via bentobox
            bento.transfer(IERC20(token), payer, recipient, value);
        }
    }
    
    /// @param sender Account that activates flash loan from bentobox
    /// @param token Token to flash borrow
    /// @param amount Token amount flash borrowed
    /// @param fee Bentobox flash loan fee
    /// @param data Data involved in flash loan
    function onFlashLoan(
        address sender,
        IERC20 token, 
        uint256 amount, 
        uint256 fee, 
        bytes calldata data
    ) external override {
        // Run router flash loan strategy through delegatecall
        (bool success, bytes memory result) = address(this).delegatecall(data);
            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }
        // Pay back borrowed token to bentobox with fee and send any winnings to `sender`.
        uint256 payback = amount + fee; // calculate `payback` to bentobox as borrowed token `amount` + `fee`
        token.transfer(msg.sender, payback); // send `payback` to bentobox or other contract supporting {IFlashBorrower}
        token.transfer(sender, token.balanceOf(address(this)) - payback); // skim remainder token winnings to `sender`
    }
    
    /// @param token The token to pay
    /// @param recipient The entity that will receive payment
    /// @param amount The amount to pay
    function _depositToBentoBox(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (token == address(0) || (token == WETH && address(this).balance >= amount)) {
            // Deposit eth into recipient bentobox
            bento.deposit{value: amount}(IERC20(address(0)), address(this), recipient, amount, 0);
        } else {
            // Deposit ERC20 token to bentobox
            bento.deposit(IERC20(token), msg.sender, recipient, amount, 0);
        }
    }

    function _depositSharesToBentoBox(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (token == address(0) || (token == WETH && address(this).balance >= amount)) {
            // Deposit eth into recipient bentobox
            bento.deposit{value: amount}(IERC20(address(0)), address(this), recipient, 0, amount);
        } else {
            // Deposit ERC20 token to bentobox
            bento.deposit(IERC20(token), msg.sender, recipient, 0, amount);
        }
    }
}

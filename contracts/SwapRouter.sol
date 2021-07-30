// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./interfaces/IBentoBoxMinimal.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ITridentRouter.sol";
import "./utils/TridentBatcher.sol";
import "hardhat/console.sol";

/// @notice Trident exchange pool router.
contract TridentRouter is ITridentRouter, TridentBatcher {
    /// @notice BentoBox token vault.
    IBentoBoxMinimal public immutable bento;
    /// @notice ERC-20 token for wrapped ETH.
    address public immutable wETH;

    constructor(IBentoBoxMinimal _bento, address _wETH) {
        _bento.registerProtocol();
        bento = _bento;
        wETH = _wETH;
    }

    // receive() external payable {
    //     require(msg.sender == wETH);
    // }

    // function exactInputSingle(ExactInputSingleParams calldata params)
    //     external
    //     payable
    //     returns (uint256 amountOut)
    // {
    //     pay(params.tokenIn, msg.sender, params.pool, params.amountIn);
    //     amountOut = IPool(params.pool).swap(params.data);
    //     require(amountOut >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
    // }

    // function exactInput(ExactInputParams calldata params)
    //     external
    //     payable
    //     returns (uint256 amountOut)
    // {
    //     // @dev Pay the first pool directly.
    //     pay(params.path[0].tokenIn, msg.sender, params.path[0].pool, params.amountIn);
    //     amountOut = _preFundedExactInput(params);
    // }

    // function exactInputSingleWithNativeToken(ExactInputSingleParams calldata params)
    //     external
    //     payable
    //     returns (uint256 amountOut)
    // {
    //     _depositToBentoBox(params.tokenIn, params.pool, params.amountIn);
    //     amountOut = IPool(params.pool).swapWithoutContext(
    //         params.tokenIn,
    //         params.tokenOut,
    //         params.recipient,
    //         params.unwrapBento
    //     );
    //     amountOut = bento.toAmount(params.tokenOut, amountOut, false);
    //     require(amountOut >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
    // }

    // function exactInputWithNativeToken(ExactInputParams calldata params)
    //     external
    //     payable
    //     returns (uint256 amountOut)
    // {
    //     _depositToBentoBox(params.path[0].tokenIn, params.path[0].pool, params.amountIn);
    //     amountOut = _preFundedExactInput(params);
    // }

    // function complexPath(ComplexPathParams calldata params) external payable {
    //     for (uint256 i; i < params.initialPath.length; i++) {
    //         if (!params.initialPath[i].preFunded) {
    //             pay(
    //                 params.initialPath[i].tokenIn,
    //                 msg.sender,
    //                 params.initialPath[i].pool,
    //                 params.initialPath[i].amountIn
    //             );
    //         }
    //         uint256 amountIn = bento.toShare(params.initialPath[i].tokenIn, params.initialPath[i].amountIn, false);
    //         IPool(params.initialPath[i].pool).swapWithContext(
    //             params.initialPath[i].tokenIn,
    //             params.initialPath[i].tokenOut,
    //             params.initialPath[i].context,
    //             address(this),
    //             false,
    //             amountIn
    //         );
    //     }

    //     for (uint256 i; i < params.percentagePath.length; i++) {
    //         uint256 balanceShares = bento.balanceOf(params.percentagePath[i].tokenIn, address(this));
    //         uint256 transferShares = (balanceShares * params.percentagePath[i].balancePercentage) / uint256(10)**6;
    //         payInShares(params.percentagePath[i].tokenIn, address(this), params.percentagePath[i].pool, transferShares);
    //         IPool(params.percentagePath[i].pool).swapWithContext(
    //             params.percentagePath[i].tokenIn,
    //             params.percentagePath[i].tokenOut,
    //             params.percentagePath[i].context,
    //             address(this),
    //             false,
    //             transferShares
    //         );
    //     }

    //     for (uint256 i; i < params.output.length; i++) {
    //         uint256 balanceShares = bento.balanceOf(params.output[i].token, address(this));
    //         uint256 balanceAmount = bento.toAmount(params.output[i].token, balanceShares, false);
    //         require(balanceAmount >= params.output[i].minAmount, "TOO_LITTLE_RECEIVED");
    //         if (params.output[i].unwrapBento) {
    //             bento.withdraw(params.output[i].token, address(this), params.output[i].to, 0, balanceShares);
    //         } else {
    //             payInShares(params.output[i].token, address(this), params.output[i].to, balanceShares);
    //         }
    //     }
    // }

    // function addLiquidity(
    //     IPool.TokenInput[] calldata tokenInput,
    //     address pool,
    //     address recipient,
    //     uint256 deadline,
    //     uint256 minLiquidity
    // ) external returns (uint256 liquidity) {
    //     for (uint256 i; i < tokenInput.length; i++) {
    //         if (tokenInput[i].native) {
    //             _depositToBentoBox(tokenInput[i].token, pool, tokenInput[i].amount);
    //         } else {
    //             uint256 shares = bento.toShare(tokenInput[i].token, tokenInput[i].amount, false);
    //             bento.transfer(tokenInput[i].token, msg.sender, pool, shares);
    //         }
    //     }
    //     liquidity = IPool(pool).mint(recipient);
    //     require(liquidity >= minLiquidity, "NOT_ENOUGH_LIQUIDITY_MINTED");
    // }

    // function burnLiquidity(
    //     address pool,
    //     address recipient,
    //     bool unwrapBento,
    //     uint256 deadline,
    //     uint256 liquidity,
    //     IPool.TokenAmount[] memory minWithdrawals
    // ) external {
    //     safeTransferFrom(pool, msg.sender, pool, liquidity);
    //     IPool.TokenAmount[] memory withdrawnLiquidity = IPool(pool).burn(recipient, unwrapBento);
    //     for (uint256 i; i < minWithdrawals.length; i++) {
    //         uint256 j;
    //         for (; j < withdrawnLiquidity.length; j++) {
    //             if (withdrawnLiquidity[j].token == minWithdrawals[i].token) {
    //                 uint256 underlyingAmount = bento.toAmount(
    //                     withdrawnLiquidity[j].token,
    //                     withdrawnLiquidity[j].amount,
    //                     false
    //                 );
    //                 require(underlyingAmount >= minWithdrawals[i].amount, "TOO_LITTLE_RECEIVED");
    //                 break;
    //             }
    //         }
    //         // @dev A token that is present in `minWithdrawals` is missing from `withdrawnLiquidity`.
    //         require(j < withdrawnLiquidity.length, "INCORRECT_TOKEN_WITHDRAWN");
    //     }
    // }

    // function burnLiquiditySingle(
    //     address pool,
    //     address tokenOut,
    //     address recipient,
    //     bool unwrapBento,
    //     uint256 deadline,
    //     uint256 liquidity,
    //     uint256 minWithdrawal
    // ) external {
    //     // @dev Use liquidity = 0 for pre funding.
    //     safeTransferFrom(pool, msg.sender, pool, liquidity);
    //     uint256 withdrawn = IPool(pool).burnLiquiditySingle(tokenOut, recipient, unwrapBento);
    //     withdrawn = bento.toAmount(tokenOut, withdrawn, false);
    //     require(withdrawn >= minWithdrawal, "TOO_LITTLE_RECEIVED");
    // }

    // function sweepBentoBoxToken(
    //     address token,
    //     uint256 amount,
    //     address recipient
    // ) external {
    //     bento.transfer(token, address(this), recipient, amount);
    // }

    // function sweepNativeToken(
    //     address token,
    //     uint256 amount,
    //     address recipient
    // ) external {
    //     safeTransfer(token, recipient, amount);
    // }

    // function refundETH() external payable {
    //     if (address(this).balance != 0) safeTransferETH(msg.sender, address(this).balance);
    // }

    // function unwrapWETH(uint256 amountMinimum, address recipient) external {
    //     uint256 balanceWETH = IERC20(wETH).balanceOf(address(this));
    //     require(balanceWETH >= amountMinimum, "INSUFFICIENT_WETH");

    //     if (balanceWETH != 0) {
    //         IWETH(wETH).withdraw(balanceWETH);
    //         safeTransferETH(recipient, balanceWETH);
    //     }
    // }

    // function _preFundedExactInput(ExactInputParams memory params) internal returns (uint256 amount) {
    //     amount = bento.toShare(params.path[0].tokenIn, params.amountIn, false);
    //     uint256 lenMinusOne = params.path.length - 1;

    //     for (uint256 i; i < lenMinusOne; i++) {
    //         amount = IPool(params.path[i].pool).swapWithoutContext(
    //             params.path[i].tokenIn,
    //             params.path[i + 1].tokenIn,
    //             params.path[i + 1].pool,
    //             false
    //         );
    //     }

    //     // @dev Last hop.
    //     amount = IPool(params.path[lenMinusOne].pool).swapWithoutContext(
    //         params.path[lenMinusOne].tokenIn,
    //         params.tokenOut,
    //         params.recipient,
    //         params.unwrapBento
    //     );

    //     amount = bento.toAmount(params.path[lenMinusOne].tokenIn, amount, false);
    //     require(amount >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
    // }

    // function _preFundedExactInputWithContext(ExactInputParamsWithContext memory params)
    //     internal
    //     returns (uint256 amount)
    // {
    //     amount = bento.toShare(params.path[0].tokenIn, params.amountIn, false);
    //     uint256 lenMinusOne = params.path.length - 1;

    //     for (uint256 i; i < lenMinusOne; i++) {
    //         amount = IPool(params.path[i].pool).swapWithContext(
    //             params.path[i].tokenIn,
    //             params.path[i + 1].tokenIn,
    //             params.path[i].context,
    //             params.path[i + 1].pool,
    //             false,
    //             amount
    //         );
    //     }

    //     amount = IPool(params.path[lenMinusOne].pool).swapWithContext(
    //         params.path[lenMinusOne].tokenIn,
    //         params.tokenOut,
    //         params.path[lenMinusOne].context,
    //         params.recipient,
    //         params.unwrapBento,
    //         amount
    //     );

    //     amount = bento.toAmount(params.path[lenMinusOne].tokenIn, amount, false);
    //     require(amount >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
    // }

    // /// @param token The token to pay.
    // /// @param payer The account that must pay.
    // /// @param recipient The account that will receive payment.
    // /// @param amount The amount to pay.
    // function pay(
    //     address token,
    //     address payer,
    //     address recipient,
    //     uint256 amount
    // ) internal {
    //     if (token == address(0) || (token == wETH && address(this).balance >= amount)) {
    //         // @dev Deposit ETH into `recipient` `bento` account.
    //         bento.deposit{value: amount}(address(0), address(this), recipient, amount, 0);
    //     } else {
    //         // @dev Process payment via `bento`.
    //         bento.transfer(token, payer, recipient, bento.toShare(token, amount, false));
    //     }
    // }

    // function payInShares(
    //     address token,
    //     address payer,
    //     address recipient,
    //     uint256 amount
    // ) internal {
    //     if (token == address(0) || (token == wETH && address(this).balance >= amount)) {
    //         // @dev Deposit ETH into `recipient` `bento` account.
    //         bento.deposit{value: amount}(address(0), address(this), recipient, 0, amount);
    //     } else {
    //         // @dev Process payment via `bento`.
    //         bento.transfer(token, payer, recipient, amount);
    //     }
    // }

    // /// @param token The token to pay.
    // /// @param recipient The account that will receive payment.
    // /// @param amount The amount to pay.
    // function _depositToBentoBox(
    //     address token,
    //     address recipient,
    //     uint256 amount
    // ) internal {
    //     if (token == address(0) || (token == wETH && address(this).balance >= amount)) {
    //         // @dev Deposit ETH into `recipient` `bento` account.
    //         bento.deposit{value: amount}(address(0), address(this), recipient, amount, 0);
    //     } else {
    //         // @dev Deposit ERC20 token into `recipient` `bento` account.
    //         bento.deposit(token, msg.sender, recipient, amount, 0);
    //     }
    // }

    // function _depositSharesToBentoBox(
    //     address token,
    //     address recipient,
    //     uint256 amount
    // ) internal {
    //     if (token == address(0) || (token == wETH && address(this).balance >= amount)) {
    //         // @dev Deposit ETH into `recipient` `bento` account.
    //         bento.deposit{value: amount}(address(0), address(this), recipient, 0, amount);
    //     } else {
    //         // @dev Deposit ERC20 token into `recipient` `bento` account.
    //         bento.deposit(token, msg.sender, recipient, 0, amount);
    //     }
    // }

    // /// @notice Provides safe ERC20.transfer for tokens that do not consistently return true/false.
    // /// @dev Reverts on failed {transfer}.
    // /// @param token Address of ERC-20 token.
    // /// @param recipient Account to send tokens to.
    // /// @param amount The token amount to send.
    // function safeTransfer(
    //     address token,
    //     address recipient,
    //     uint256 amount
    // ) internal {
    //     (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, recipient, amount)); // @dev transfer(address,uint256).
    //     require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    // }

    // /// @notice Provides safe ERC20.transferFrom for tokens that do not consistently return true/false.
    // /// @dev Reverts on failed {transferFrom}.
    // /// @param token Address of ERC-20 token.
    // /// @param from Account to send tokens from.
    // /// @param recipient Account to send tokens to.
    // /// @param amount Token amount to send.
    // function safeTransferFrom(
    //     address token,
    //     address from,
    //     address recipient,
    //     uint256 amount
    // ) internal {
    //     (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, recipient, amount)); // @dev transferFrom(address,address,uint256).
    //     require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    // }

    // /// @notice Provides safe ETH transfer.
    // /// @dev Reverts on failed {call}.
    // /// @param recipient Account to send ETH.
    // /// @param amount ETH amount to send.
    // function safeTransferETH(address recipient, uint256 amount) internal {
    //     (bool success, ) = recipient.call{value: amount}("");
    //     require(success, "ETH_TRANSFER_FAILED");
    // }
}

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

    receive() external payable {
        require(msg.sender == wETH);
    }

    function exactInputSingle(ExactInputSingleParams calldata params) public payable returns (uint256 amountOut) {
        bento.transfer(params.tokenIn, msg.sender, params.pool, params.amountIn);
        amountOut = IPool(params.pool).swap(params.data);
        require(amountOut >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
    }

    function exactInput(ExactInputParams calldata params) public payable returns (uint256 amountOut) {
        // @dev Pay the first pool directly.
        bento.transfer(params.tokenIn, msg.sender, params.path[0].pool, params.amountIn);
        for (uint256 i; i < params.path.length; i++) {
            amountOut = IPool(params.path[i].pool).swap(params.path[i].data);
        }
        require(amountOut >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
    }

    function exactInputSingleWithNativeToken(ExactInputSingleParams calldata params)
        public
        payable
        returns (uint256 amountOut)
    {
        _depositToBentoBox(params.tokenIn, params.pool, params.amountIn);
        amountOut = IPool(params.pool).swap(params.data);
        require(amountOut >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
    }

    function exactInputWithNativeToken(ExactInputParams calldata params) public payable returns (uint256 amountOut) {
        _depositToBentoBox(params.tokenIn, params.path[0].pool, params.amountIn);
        for (uint256 i; i < params.path.length; i++) {
            amountOut = IPool(params.path[i].pool).swap(params.path[i].data);
        }
        require(amountOut >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
    }

    function complexPath(ComplexPathParams calldata params) public payable {
        for (uint256 i; i < params.initialPath.length; i++) {
            if (params.initialPath[i].native) {
                _depositToBentoBox(
                    params.initialPath[i].tokenIn,
                    params.initialPath[i].pool,
                    params.initialPath[i].amount
                );
            } else {
                bento.transfer(
                    params.initialPath[i].tokenIn,
                    msg.sender,
                    params.initialPath[i].pool,
                    params.initialPath[i].amount
                );
            }
            IPool(params.initialPath[i].pool).swap(params.initialPath[i].data);
        }

        for (uint256 i; i < params.percentagePath.length; i++) {
            uint256 balanceShares = bento.balanceOf(params.percentagePath[i].tokenIn, address(this));
            uint256 transferShares = (balanceShares * params.percentagePath[i].balancePercentage) / uint256(10)**6;
            bento.transfer(
                params.percentagePath[i].tokenIn,
                address(this),
                params.percentagePath[i].pool,
                transferShares
            );
            IPool(params.percentagePath[i].pool).swap(params.percentagePath[i].data);
        }

        for (uint256 i; i < params.output.length; i++) {
            uint256 balanceShares = bento.balanceOf(params.output[i].token, address(this));
            uint256 balanceAmount = bento.toAmount(params.output[i].token, balanceShares, false);
            require(balanceAmount >= params.output[i].minAmount, "TOO_LITTLE_RECEIVED");
            if (params.output[i].unwrapBento) {
                bento.withdraw(params.output[i].token, address(this), params.output[i].to, 0, balanceShares);
            } else {
                bento.transfer(params.output[i].token, address(this), params.output[i].to, balanceShares);
            }
        }
    }

    function addLiquidity(
        TokenInput[] memory tokenInput,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) public returns (uint256 liquidity) {
        for (uint256 i; i < tokenInput.length; i++) {
            if (tokenInput[i].native) {
                _depositToBentoBox(tokenInput[i].token, pool, tokenInput[i].amount);
            } else {
                bento.transfer(tokenInput[i].token, msg.sender, pool, tokenInput[i].amount);
            }
        }
        liquidity = IPool(pool).mint(data);
        require(liquidity >= minLiquidity, "NOT_ENOUGH_LIQUIDITY_MINTED");
    }

    function burnLiquidity(
        address pool,
        uint256 liquidity,
        bytes calldata data,
        IPool.TokenAmount[] memory minWithdrawals
    ) public {
        safeTransferFrom(pool, msg.sender, pool, liquidity);
        IPool.TokenAmount[] memory withdrawnLiquidity = IPool(pool).burn(data);
        for (uint256 i; i < minWithdrawals.length; i++) {
            uint256 j;
            for (; j < withdrawnLiquidity.length; j++) {
                if (withdrawnLiquidity[j].token == minWithdrawals[i].token) {
                    require(withdrawnLiquidity[j].amount >= minWithdrawals[i].amount, "TOO_LITTLE_RECEIVED");
                    break;
                }
            }
            // @dev A token that is present in `minWithdrawals` is missing from `withdrawnLiquidity`.
            require(j < withdrawnLiquidity.length, "INCORRECT_TOKEN_WITHDRAWN");
        }
    }

    function burnLiquiditySingle(
        address pool,
        uint256 liquidity,
        bytes calldata data,
        uint256 minWithdrawal
    ) public {
        // @dev Use liquidity = 0 for pre funding.
        safeTransferFrom(pool, msg.sender, pool, liquidity);
        uint256 withdrawn = IPool(pool).burnSingle(data);
        require(withdrawn >= minWithdrawal, "TOO_LITTLE_RECEIVED");
    }

    function sweepBentoBoxToken(
        address token,
        uint256 amount,
        address recipient
    ) external {
        bento.transfer(token, address(this), recipient, amount);
    }

    function sweepNativeToken(
        address token,
        uint256 amount,
        address recipient
    ) external {
        safeTransfer(token, recipient, amount);
    }

    function refundETH() external payable {
        if (address(this).balance != 0) safeTransferETH(msg.sender, address(this).balance);
    }

    function unwrapWETH(uint256 amountMinimum, address recipient) external {
        uint256 balanceWETH = IERC20(wETH).balanceOf(address(this));
        require(balanceWETH >= amountMinimum, "INSUFFICIENT_WETH");

        if (balanceWETH != 0) {
            IWETH(wETH).withdraw(balanceWETH);
            safeTransferETH(recipient, balanceWETH);
        }
    }

    /// @param token The token to pay.
    /// @param recipient The account that will receive payment.
    /// @param amount The amount to pay.
    function _depositToBentoBox(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (token == wETH && address(this).balance > 0) {
            uint256 underlyingAmount = bento.toAmount(wETH, amount, true);
            if (address(this).balance > underlyingAmount) {
                // @dev Deposit ETH into `recipient` `bento` account.
                bento.deposit{value: underlyingAmount}(address(0), address(this), recipient, 0, amount);
                return;
            }
        }
        // @dev Deposit ERC20 token into `recipient` `bento` account.
        bento.deposit(token, msg.sender, recipient, amount, 0);
    }

    /// @notice Provides safe ERC20.transfer for tokens that do not consistently return true/false.
    /// @dev Reverts on failed {transfer}.
    /// @param token Address of ERC-20 token.
    /// @param recipient Account to send tokens to.
    /// @param amount The token amount to send.
    function safeTransfer(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, recipient, amount)); // @dev transfer(address,uint256).
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    /// @notice Provides safe ERC20.transferFrom for tokens that do not consistently return true/false.
    /// @dev Reverts on failed {transferFrom}.
    /// @param token Address of ERC-20 token.
    /// @param from Account to send tokens from.
    /// @param recipient Account to send tokens to.
    /// @param amount Token amount to send.
    function safeTransferFrom(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, recipient, amount)); // @dev transferFrom(address,address,uint256).
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    /// @notice Provides safe ETH transfer.
    /// @dev Reverts on failed {call}.
    /// @param recipient Account to send ETH.
    /// @param amount ETH amount to send.
    function safeTransferETH(address recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH_TRANSFER_FAILED");
    }
}

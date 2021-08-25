// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./interfaces/IBentoBoxMinimal.sol";
import "./interfaces/IPool.sol";
import "./interfaces/ITridentRouter.sol";
import "./utils/TridentHelper.sol";

/// @notice Trident pool router contract.
contract TridentRouter is ITridentRouter, TridentHelper {
    /// @notice BentoBox token vault.
    IBentoBoxMinimal public immutable bento;

    address internal cachedMsgSender;
    address internal cachedPool;

    constructor(IBentoBoxMinimal _bento, address _wETH) TridentHelper(_wETH) {
        _bento.registerProtocol();
        bento = _bento;
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

    function exactInputLazy(uint256 amountOutMinimum, Path[] calldata path) public payable returns (uint256 amountOut) {
        for (uint256 i; i < path.length; i++) {
            cachedMsgSender = msg.sender;
            cachedPool = path[i].pool;
            amountOut = IPool(path[i].pool).swap(path[i].data);
        }
        require(amountOut >= amountOutMinimum, "TOO_LITTLE_RECEIVED");
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
    ) public payable returns (uint256 liquidity) {
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

    function addLiquidityLazy(address pool, bytes calldata data) public payable {
        cachedMsgSender = msg.sender;
        cachedPool = pool;
        // @dev The pool must ensure that there's not too much slippage.
        IPool(pool).mint(data);
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
        // @dev Use 'liquidity = 0' for prefunding.
        safeTransferFrom(pool, msg.sender, pool, liquidity);
        uint256 withdrawn = IPool(pool).burnSingle(data);
        require(withdrawn >= minWithdrawal, "TOO_LITTLE_RECEIVED");
    }

    function tridentSwapCallback(bytes calldata data) external {
        require(msg.sender == cachedPool, "UNAUTHORIZED_CALLBACK");

        TokenInput memory tokenInput = abi.decode(data, (TokenInput));

        // @dev Transfer the requested token to the pool.
        if (tokenInput.native) {
            _depositFromUserToBentoBox(tokenInput.token, cachedMsgSender, msg.sender, tokenInput.amount);
        } else {
            bento.transfer(tokenInput.token, cachedMsgSender, msg.sender, tokenInput.amount);
        }

        // @dev Resets the msg.sender's authorization.
        cachedMsgSender = address(1);
    }

    function tridentMintCallback(bytes calldata data) external {
        require(msg.sender == cachedPool, "UNAUTHORIZED_CALLBACK");

        TokenInput[] memory tokenInput = abi.decode(data, (TokenInput[]));

        // @dev Transfer the requested tokens to the pool.
        for (uint256 i; i < tokenInput.length; i++) {
            if (tokenInput[i].native) {
                _depositFromUserToBentoBox(tokenInput[i].token, cachedMsgSender, msg.sender, tokenInput[i].amount);
            } else {
                bento.transfer(tokenInput[i].token, cachedMsgSender, msg.sender, tokenInput[i].amount);
            }
        }

        // @dev Resets the msg.sender's authorization.
        cachedMsgSender = address(1);
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
        uint256 balanceWETH = balanceOfThis(wETH);
        require(balanceWETH >= amountMinimum, "INSUFFICIENT_WETH");

        if (balanceWETH != 0) {
            withdrawFromWETH(balanceWETH);
            safeTransferETH(recipient, balanceWETH);
        }
    }

    function _depositToBentoBox(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (token == wETH && address(this).balance != 0) {
            uint256 underlyingAmount = bento.toAmount(wETH, amount, true);
            if (address(this).balance > underlyingAmount) {
                // @dev Deposit ETH into `recipient` `bento` account.
                bento.deposit{value: underlyingAmount}(address(0), address(this), recipient, 0, amount);
                return;
            }
        }
        // @dev Deposit ERC-20 token into `recipient` `bento` account.
        bento.deposit(token, msg.sender, recipient, 0, amount);
    }

    function _depositFromUserToBentoBox(
        address token,
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        if (token == wETH && address(this).balance != 0) {
            uint256 underlyingAmount = bento.toAmount(wETH, amount, true);
            if (address(this).balance > underlyingAmount) {
                // @dev Deposit ETH into `recipient` `bento` account.
                bento.deposit{value: underlyingAmount}(address(0), address(this), recipient, 0, amount);
                return;
            }
        }
        // @dev Deposit ERC-20 token into `recipient` `bento` account.
        bento.deposit(token, sender, recipient, 0, amount);
    }
}

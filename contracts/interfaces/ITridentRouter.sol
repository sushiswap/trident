// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident exchange pool router interface.
interface ITridentRouter {
    struct Path {
        address pool;
        bytes data;
    }

    struct ExactInputSingleParams {
        uint256 amountIn;
        uint256 amountOutMinimum;
        address pool;
        address tokenIn;
        bytes data;
    }

    struct ExactInputParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        Path[] path;
    }

    struct InitialPath {
        address tokenIn;
        address pool;
        address tokenOut;
        bool preFunded;
        uint256 amountIn; // @dev 0 amountIn implies pre-funding.
        bytes context;
    }

    struct PercentagePath {
        address tokenIn;
        address pool;
        address tokenOut;
        uint64 balancePercentage; // @dev Multiplied by 10^6.
        bytes context;
    }

    struct Output {
        address token;
        address to;
        bool unwrapBento;
        uint256 minAmount;
    }

    struct ComplexPathParams {
        uint256 deadline;
        InitialPath[] initialPath;
        PercentagePath[] percentagePath;
        Output[] output;
    }
}

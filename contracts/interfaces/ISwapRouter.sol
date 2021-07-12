// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface ISwapRouter {
    // TODO: Make context optional

    /// @dev In case of a multi hop swap, the output token for first swap is the input token of the next swap
    struct Path {
        address tokenIn;
        address pool;
    }

    struct PathWithContext {
        address tokenIn;
        address pool;
        bytes context;
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        address pool;
        address recipient;
        bool unwrapBento;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct ExactInputSingleParamsWithContext {
        address tokenIn;
        address tokenOut;
        address pool;
        address recipient;
        bool unwrapBento;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        bytes context;
    }

    struct ExactInputParams {
        Path[] path;
        address tokenOut;
        address recipient;
        bool unwrapBento;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct ExactInputParamsWithContext {
        PathWithContext[] path;
        address tokenOut;
        address recipient;
        bool unwrapBento;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct InitialPath {
        address tokenIn;
        address pool;
        address tokenOut;
        bool preFunded;
        uint256 amountIn; // 0 amountIn implies pre-funding
        bytes context;
    }

    struct PercentagePath {
        address tokenIn;
        address pool;
        address tokenOut;
        uint64 balancePercentage; // Multiplied by 10^6
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

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface ISwapRouter {
    // TODO: Make context optional
    // Split exact imput and exact output swaps in pool

    /// @dev In case of a multi hop swap, the output token for first swap is the input token of the next swap
    struct Path {
        address tokenIn;
        address pool;
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

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        Path[] path;
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

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

import "./IUniswapV2Pair.sol";

interface IMirinPool is IUniswapV2Pair {
    event OperatorSet(address indexed previousOperator, address indexed newOperator);
    event SwapFeeUpdated(uint8 newFee);
    event SwapFeeToUpdated(address newFeeTo);
    event BlacklistAdded(address indexed account);
    event BlacklistRemoved(address indexed account);
    event OptionCreated(
        uint256 id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 strike,
        uint256 created,
        uint256 expire
    );
    event OptionExercised(
        uint256 id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 strike,
        uint256 excercised,
        uint256 expire
    );

    function MIN_SWAP_FEE() external view returns (uint8);

    function MAX_SWAP_FEE() external view returns (uint8);

    function operator() external view returns (address);

    function swapFee() external view returns (uint8);

    function swapFeeTo() external view returns (address);

    function blacklisted(address account) external view returns (bool);

    function setOperator(address newOperator) external;

    function updateSwapFee(uint8 newFee) external;

    function updateSwapFeeTo(address newFeeTo) external;

    function disable(address to) external;

    function addToBlacklist(address[] calldata accounts) external;

    function removeFromBlacklist(address[] calldata accounts) external;

    function weight0() external view returns (uint8);

    function weight1() external view returns (uint8);

    function pricePoints(uint256)
        external
        view
        returns (
            uint256 timestamp,
            uint256 price0Cumulative,
            uint256 price1Cumulative
        );

    function getWeights() external view returns (uint8 _weight0, uint8 _weight1);

    function pricePointsLength() external view returns (uint256);

    function price(address token) external view returns (uint256);

    function realizedVariance(
        address tokenIn,
        uint256 p,
        uint256 window
    ) external view returns (uint256);

    function realizedVolatility(
        address tokenIn,
        uint256 p,
        uint256 window
    ) external view returns (uint256);

    function quotePrice(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut);

    function sample(
        address tokenIn,
        uint256 amountIn,
        uint256 p,
        uint256 window
    ) external view returns (uint256[] memory);

    function loanContracts() external view returns (address);

    function optionContracts() external view returns (address);

    function quoteOption(address tokenIn, uint256 t) external view returns (uint256 call, uint256 put);

    function quoteOptionPrice(
        address tokenIn,
        uint256 t,
        uint256 sp,
        uint256 st
    ) external view returns (uint256 call, uint256 put);

    function options(uint256)
        external
        view
        returns (
            address asset,
            uint256 amount,
            uint256 strike,
            uint256 expire,
            uint256 optionType
        );

    function optionsLength() external view returns (uint256);

    function feeDetail(
        address token,
        uint256 st,
        uint256 t,
        uint256 optionType
    )
        external
        view
        returns (
            uint256 _call,
            uint256 _put,
            uint256 _fee
        );

    function fee(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 optionType
    ) external view returns (uint256);

    function callATM(
        address token,
        uint256 amount,
        uint256 t,
        uint256 maxFee
    ) external;

    function putATM(
        address token,
        uint256 amount,
        uint256 t,
        uint256 maxFee
    ) external;

    function createCall(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 maxFee
    ) external;

    function createPut(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 maxFee
    ) external;

    function utilization(
        address token,
        uint256 optionType,
        uint256 amount
    ) external view returns (uint256);

    function createOption(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 optionType,
        uint256 maxFee
    ) external;

    function exerciseOptionProfitOnly(uint256 id) external;

    function exerciseOption(uint256 id) external;

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external;

    function burn(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external returns (uint256 amount0, uint256 amount1);
}

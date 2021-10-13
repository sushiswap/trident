// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IPool.sol";
import "./IBentoBoxMinimal.sol";
import "./IMasterDeployer.sol";
import "../libraries/concentratedPool/Ticks.sol";

/// @notice Trident Concentrated Liquidity Pool interface.
interface IConcentratedLiquidityPool is IPool {
    function price() external view returns (uint160);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function ticks(int24 _tick) external view returns (Ticks.Tick memory tick);

    function feeGrowthGlobal0() external view returns (uint256);

    function rangeFeeGrowth(int24 lowerTick, int24 upperTick) external view returns (uint256 feeGrowthInside0, uint256 feeGrowthInside1);

    function collect(
        int24,
        int24,
        address,
        bool
    ) external returns (uint256 amount0fees, uint256 amount1fees);

    function getImmutables()
        external
        view
        returns (
            uint128 _MAX_TICK_LIQUIDITY,
            uint24 _tickSpacing,
            uint24 _swapFee,
            address _barFeeTo,
            IBentoBoxMinimal _bento,
            IMasterDeployer _masterDeployer,
            address _token0,
            address _token1
        );

    function getPriceAndNearestTicks() external view returns (uint160 _price, int24 _nearestTick);

    function getTokenProtocolFees() external view returns (uint128 _token0ProtocolFee, uint128 _token1ProtocolFee);

    function getReserves() external view returns (uint128 _reserve0, uint128 _reserve1);

    function getSecondsGrowthAndLastObservation() external view returns (uint160 _secondGrowthGlobal, uint32 _lastObservation);

    function getAmountsForLiquidity(
        uint256 priceLower,
        uint256 priceUpper,
        uint256 currentPrice,
        uint256 liquidityAmount,
        bool roundUp
    ) external pure returns (uint128 token0amount, uint128 token1amount);
}

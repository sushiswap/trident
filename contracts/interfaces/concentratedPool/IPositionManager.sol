// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident concentrated Liquidity pool mint callback receiver.
interface IPositionManager {
    function positionMintCallback(
        address recipient,
        int24 lower,
        int24 upper,
        uint128 amount,
        uint256 feeGrowthInside0,
        uint256 feeGrowthInside1,
        uint256 positionId
    ) external returns (uint256 _positionId);
}

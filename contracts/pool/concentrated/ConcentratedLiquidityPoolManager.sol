// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IPool.sol";

/// @dev combines the nonfungible position manager and the staking contract in one
contract ConcentratedLiquidityPoolManager {
    struct Position {
        int24 lower;
        int24 upper;
        uint128 liquidity;
        address owner;
        uint256 feeGrowthInside0Last;
    }

    uint256 public positionCount;

    mapping(uint256 => Position) public positions;

    function mint(IPool pool, bytes memory mintData) public {
        (, int24 lower, , int24 upper, uint128 amount, address recipient) = abi.decode(
            mintData,
            (int24, int24, int24, int24, uint128, address)
        );

        pool.mint(mintData);

        positions[positionCount++] = Position(lower, upper, amount, recipient, 0);
    }

    function burn(IPool pool, bytes memory data) public {}

    // transfers the funds
    function mintCallback() external {}
}

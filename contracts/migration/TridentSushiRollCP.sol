// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../abstract/SelfPermit.sol";
import "../abstract/Multicall.sol";
import "../interfaces/IUniswapV2Minimal.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/ITridentRouter.sol";
import "../interfaces/IMasterDeployer.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IConstantProductPool.sol";

/// @notice Liquidity migrator from UniV2 style pool to Trident Constant product pool.
contract TridentSushiRollCP is SelfPermit, Multicall {
    error MinimumOutput();

    IBentoBoxMinimal internal immutable bentoBox;
    IPoolFactory internal immutable poolFactory;
    IMasterDeployer internal immutable masterDeployer;

    constructor(
        IBentoBoxMinimal _bentoBox,
        IPoolFactory _poolFactory,
        IMasterDeployer _masterDeployer
    ) {
        bentoBox = _bentoBox;
        poolFactory = _poolFactory;
        masterDeployer = _masterDeployer;
    }

    /** @notice Function to migrate existing Sushiswap or other Uniswap V2 style pools to Trident.
        @param pair Uniswap V2 style liquidity pool address.
        @param amount Liquidity amount (Lp token balance) to be migrated.
        @param swapFee Swap fee of the Trident CP pool we are migrating into.
        @param twapSupport Whether the Trident CP pool we are migrating into supports twap oracles.
        @param minToken0Received Slippage protection for removing liquidity from a UniV2 style pool.
        @param minToken1Received Slippage protection for removing liquidity from a UniV2 style pool.
        @param minLpReceived Slippage protection for minting liquidity on the Trident CP pool.
        @dev If the pool with the current conditions doesn't exist it will be deployed. */
    function migrate(
        IUniswapV2Minimal pair,
        uint256 amount,
        uint256 swapFee,
        bool twapSupport,
        uint256 minToken0Received,
        uint256 minToken1Received,
        uint256 minLpReceived
    ) external returns (uint256 liquidity) {
        pair.transferFrom(msg.sender, address(pair), amount);
        (uint256 amount0, uint256 amount1) = pair.burn(address(bentoBox));

        if (amount0 < minToken0Received || amount1 < minToken1Received) revert MinimumOutput();

        address token0 = pair.token0();
        address token1 = pair.token1();

        bytes memory poolData = abi.encode(token0, token1, swapFee, twapSupport);
        address tridentPool = poolFactory.configAddress(keccak256(poolData));

        if (tridentPool == address(0)) {
            tridentPool = masterDeployer.deployPool(address(poolFactory), poolData);
            bentoBox.deposit(token0, address(bentoBox), tridentPool, amount0, 0);
            bentoBox.deposit(token1, address(bentoBox), tridentPool, amount1, 0);

            liquidity = IPool(tridentPool).mint(abi.encode(msg.sender));

            if (liquidity < minLpReceived) revert MinimumOutput();
        } else {
            (uint256 reserveA, uint256 reserveB, ) = IConstantProductPool(tridentPool).getNativeReserves();
            (uint256 amount0Desired, uint256 amount1Desired) = getAmounts(amount0, amount1, reserveA, reserveB);
            bentoBox.deposit(token0, address(bentoBox), tridentPool, amount0Desired, 0);
            bentoBox.deposit(token1, address(bentoBox), tridentPool, amount1Desired, 0);

            liquidity = IPool(tridentPool).mint(abi.encode(msg.sender));

            if (liquidity < minLpReceived) revert MinimumOutput();

            if (amount0 > amount0Desired) {
                IERC20(token0).transfer(msg.sender, amount0 - amount0Desired);
            }
            if (amount1 > amount1Desired) {
                IERC20(token1).transfer(msg.sender, amount1 - amount1Desired);
            }
        }
    }

    function getAmounts(
        uint256 _amount0,
        uint256 _amount1,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint256 amount1Optimal = (_amount0 * reserveB) / reserveA;
        if (amount1Optimal <= amount1) {
            (amount0, amount1) = (_amount0, amount1Optimal);
        } else {
            uint256 amount0Optimal = (_amount1 * reserveA) / reserveB;
            (amount0, amount1) = (amount0Optimal, _amount1);
        }
    }
}

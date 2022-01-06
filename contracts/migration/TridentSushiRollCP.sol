// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >= 0.8.0;

import "../utils/TridentBatchable.sol";
import "../utils/TridentPermit.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/ITridentRouter.sol";
import "../interfaces/IMasterDeployer.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IUniswapV2Minimal.sol";
import "../interfaces/IPool.sol";

/// @notice Liquidity migrator from UniV2 style pool to Trident Constant product pool.
contract TridentSushiRollCP is TridentBatchable, TridentPermit {
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
        @param minReceived Slippage protection for minting liquidity on the Trident CP pool.
        @dev If the pool with the current conditions doesn't exist it will be deployed. */
    function migrate(
        IUniswapV2Minimal pair,
        uint256 amount,
        uint256 swapFee,
        bool twapSupport,
        uint256 minReceived
    ) external returns (uint256 liquidity) {
        address token0 = pair.token0();
        address token1 = pair.token1();

        bytes memory poolData = abi.encode(token0, token1, swapFee, twapSupport);
        address tridentPool = poolFactory.configAddress(keccak256(poolData));

        if (tridentPool == address(0)) {
            tridentPool = masterDeployer.deployPool(address(poolFactory), poolData);
        }

        pair.transferFrom(msg.sender, address(pair), amount);
        (uint256 amount0, uint256 amount1) = pair.burn(address(bentoBox));

        bentoBox.deposit(token0, address(bentoBox), tridentPool, amount0, 0);
        bentoBox.deposit(token1, address(bentoBox), tridentPool, amount1, 0);

        liquidity = IPool(tridentPool).mint(abi.encode(msg.sender));

        if (liquidity < minReceived) revert MinimumOutput();
    }
}

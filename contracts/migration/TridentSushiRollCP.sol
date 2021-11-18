// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.7;

import "../utils/TridentBatchable.sol";
import "../utils/TridentPermit.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/ITridentRouter.sol";
import "../interfaces/IMasterDeployer.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPool.sol";

/// @notice Minimal Uniswap V2 LP interface.
interface IUniswapV2Minimal is IERC20 {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

/// @notice Minimal Trident pool router interface.
interface ITridentRouterMinimal is ITridentRouter {
    /// @notice Add liquidity to a pool.
    /// @param tokenInput Token address and amount to add as liquidity.
    /// @param pool Pool address to add liquidity to.
    /// @param minLiquidity Minimum output liquidity - caps slippage.
    /// @param data Data required by the pool to add liquidity.
    function addLiquidity(
        TokenInput[] calldata tokenInput,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) external payable returns (uint256 liquidity);
}

/// @notice Liquidity migrator for Trident from popular pool types.
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

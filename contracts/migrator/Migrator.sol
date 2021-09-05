// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IntermediaryToken.sol";
import "../interfaces/IMasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IMigrator.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IPool.sol";

interface IOldPool {
    /// @notice Returns liquidity token balance per ERC-20.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the first token in the pair pool.
    function token0() external view returns (address);

    /// @notice Returns the second token in the pair pool.
    function token1() external view returns (address);

    /// @notice Returns the token supply in the pair pool per ERC-20.
    function totalSupply() external view returns (uint256);

    /// @notice Burns liquidity tokens from a legacy SushiSwap pair pool.
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /// @notice Mints Trident pool liquidity tokens.
    function mint(bytes calldata data) external returns (uint256 liquidity);

    /// @notice Pulls tokens per ERC-20.
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /// @notice Pool's reserves
    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );
}

interface IConstantProductPool is IPool {
    /// @notice Returns the token supply in the pair pool per ERC-20.
    function totalSupply() external view returns (uint256);
}

interface IMasterChef {
    /// @notice Returns desired amount of liquidity tokens for migration.
    function desiredLiquidity() external view returns (uint256);
}

/// @notice Trident pool migrator contract for legacy SushiSwap.
/// Deploys every existing pool without a twap.
contract Migrator {
    address public immutable bento;
    address public immutable masterDeployer;
    address public immutable constantProductPoolFactory;
    address public immutable masterChef;
    uint256 public desiredLiquidity = type(uint256).max;

    constructor(
        address _bento,
        address _masterDeployer,
        address _constantProductPoolFactory,
        address _masterChef
    ) {
        bento = _bento;
        masterDeployer = _masterDeployer;
        constantProductPoolFactory = _constantProductPoolFactory;
        masterChef = _masterChef;
    }

    /// @notice Migration method to replace legacy SushiSwap liquidity tokens with Trident position.
    /// @param oldPool Legacy SushiSwap pair pool.
    function migrate(IOldPool oldPool) external returns (address) {
        require(msg.sender == address(masterChef), "NOT_CHEF");
        /// @dev Get pools's tokens
        address token0 = oldPool.token0();
        address token1 = oldPool.token1();

        /// @dev Fetch pool address
        bytes memory deployData = abi.encode(token0, token1, 10, false);
        address pool = IPoolFactory(constantProductPoolFactory).configAddress(deployData);

        /// @dev If `newPool` is uninitialized, deploy on Trident.
        if (pool == address(0)) pool = IPoolFactory(constantProductPoolFactory).deployPool(deployData);

        /// @dev get LP token balance that will be migrated
        uint256 lpBalance = oldPool.balanceOf(address(masterChef));

        /// @dev noting to migrate
        if (lpBalance == 0) return pool;

        /// @dev transfer funds to BentoBox
        oldPool.transferFrom(address(masterChef), address(oldPool), lpBalance);
        (uint256 amount0, uint256 amount1) = oldPool.burn(address(bento));
        IBentoBoxMinimal(bento).deposit(token0, address(bento), pool, amount0, 0);
        IBentoBoxMinimal(bento).deposit(token1, address(bento), pool, amount1, 0);

        /// @dev if pool already exist use an intermediary token to ensure Master Chef receives the same balance
        if (IConstantProductPool(pool).totalSupply() == 0) {
            desiredLiquidity = lpBalance;

            IPool(pool).mint(abi.encode(masterChef));

            desiredLiquidity = type(uint256).max;

            return pool;
        } else {
            address intermediaryToken = address(new IntermediaryToken(pool, masterChef, lpBalance));

            (uint112 _reserve0, uint112 _reserve1, ) = oldPool.getReserves();
            uint256 oldPoolPrice = (1e18 * amount0) / amount1;
            uint256 newPoolPrice = (uint256(_reserve0) * 1e18) / uint256(_reserve1);
            uint256 priceChange = (1e4 * oldPoolPrice) / newPoolPrice;

            require(priceChange < 10050 && priceChange > 9950, "Price difference too big"); // allow for 0.5% pool price difference

            IPool(pool).mint(abi.encode(intermediaryToken));

            return intermediaryToken;
        }
    }
}

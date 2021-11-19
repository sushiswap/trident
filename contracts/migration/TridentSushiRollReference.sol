// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/TridentBatchable.sol";
import "../utils/TridentPermit.sol";

/// @notice Interface for handling Balancer V1 LP.
interface IBalancerV1 {
    function getFinalTokens() external view returns (address[] memory);

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;
}

/// @notice Interface for handling Balancer V2 LP - `assets` aliased to address for code simplicity.
interface IBalancerV2 {
    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    /// @notice Returns asset tokens from a Balancer V2 pool.
    function getPoolTokens(bytes32 poolId) external view returns (address[] memory);

    /// @notice Exits liquidity tokens from a Balancer V2 pool.
    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest calldata request
    ) external;
}

/// @notice Minimal Uniswap V2 LP interface.
interface IUniswapV2Minimal {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

/// @notice Interface for handling Uniswap V3 LP.
interface IUniswapV3 {
    /// @notice Returns the position information associated with a given token ID.
    /// @dev Throws if the token ID is not valid.
    /// @param tokenId The ID of the token that represents the position
    /// @return nonce The nonce for permits
    /// @return operator The address that is approved for spending
    /// @return token0 The address of the token0 for a specific pool
    /// @return token1 The address of the token1 for a specific pool
    /// @return fee The fee associated with the pool
    /// @return tickLower The lower end of the tick range for the position
    /// @return tickUpper The higher end of the tick range for the position
    /// @return liquidity The liquidity of the position
    /// @return feeGrowthInside0LastX128 The fee growth of token0 as of the last action on the individual position
    /// @return feeGrowthInside1LastX128 The fee growth of token1 as of the last action on the individual position
    /// @return tokensOwed0 The uncollected amount of token0 owed to the position as of the last computation
    /// @return tokensOwed1 The uncollected amount of token1 owed to the position as of the last computation
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    // @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @param params tokenId The ID of the NFT for which tokens are being collected,
    /// recipient The account that should receive the tokens,
    /// amount0Max The maximum amount of token0 to collect,
    /// amount1Max The maximum amount of token1 to collect
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

/// @notice Minimal Trident pool router interface.
interface ITridentRouterMinimal {
    struct TokenInput {
        address token;
        bool native;
        uint256 amount;
    }

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
contract TridentSushiRoll {
    /* IBalancerV2 internal immutable balancerVault;
    IUniswapV3 internal immutable uniNonfungiblePositionManager;
    ITridentRouterMinimal internal immutable tridentRouter;

    constructor(
        IBalancerV2 _balancerVault,
        IUniswapV3 _uniNonfungiblePositionManager,
        ITridentRouterMinimal _tridentRouter
    ) {
        balancerVault = _balancerVault;
        uniNonfungiblePositionManager = _uniNonfungiblePositionManager;
        tridentRouter = _tridentRouter;
    }

    // **** BAL MIGRATOR **** //
    // --------------------- //

    function migrateFromBalancerV1toTrident(
        IBalancerV1 bPool,
        uint256 poolAmountIn,
        uint256[] calldata minAmountsOut,
        address tridentPool,
        uint256 minLiquidity,
        bytes calldata data
    ) external returns (uint256 liquidity) {
        address[] memory tokens = bPool.getFinalTokens();

        bPool.exitPool(poolAmountIn, minAmountsOut);

        ITridentRouterMinimal.TokenInput[] memory input = new ITridentRouterMinimal.TokenInput[](tokens.length);

        unchecked {
            for (uint256 i; i < tokens.length; i++) {
                input[i].token = tokens[i];
                input[i].native = true;
                input[i].amount = IERC20(tokens[i]).balanceOf(address(this));
                IERC20(tokens[i]).approve(address(tridentRouter), input[i].amount);
            }
        }

        liquidity = tridentRouter.addLiquidity(input, tridentPool, minLiquidity, data);
    }

    function migrateFromBalancerV2toTrident(
        bytes32 poolId,
        IBalancerV2.ExitPoolRequest calldata request,
        address tridentPool,
        uint256 minLiquidity,
        bytes calldata data
    ) external returns (uint256 liquidity) {
        address[] memory tokens = balancerVault.getPoolTokens(poolId);

        balancerVault.exitPool(poolId, msg.sender, address(this), request);

        ITridentRouterMinimal.TokenInput[] memory input = new ITridentRouterMinimal.TokenInput[](tokens.length);

        unchecked {
            for (uint256 i; i < tokens.length; i++) {
                input[i].token = tokens[i];
                input[i].native = true;
                input[i].amount = IERC20(tokens[i]).balanceOf(address(this));
                IERC20(tokens[i]).approve(address(tridentRouter), input[i].amount);
            }
        }

        liquidity = tridentRouter.addLiquidity(input, tridentPool, minLiquidity, data);
    }

    // **** UNI MIGRATOR **** //
    // --------------------- //

    function migrateFromUniswapV2toTrident(
        address pair,
        uint256 _liquidity,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) external returns (uint256 liquidity) {
        IERC20(pair).transferFrom(msg.sender, address(pair), _liquidity);

        IUniswapV2Minimal(pair).burn(address(this));

        ITridentRouterMinimal.TokenInput[] memory input = new ITridentRouterMinimal.TokenInput[](2);

        IERC20 token0 = IERC20(IUniswapV2Minimal(pair).token0());
        IERC20 token1 = IERC20(IUniswapV2Minimal(pair).token1());

        input[0].token = address(token0);
        input[0].native = true;
        input[0].amount = token0.balanceOf(address(this));

        input[1].token = address(token1);
        input[1].native = true;
        input[1].amount = token1.balanceOf(address(this));

        token0.approve(address(tridentRouter), input[0].amount);
        token1.approve(address(tridentRouter), input[1].amount);

        liquidity = ITridentRouterMinimal(tridentRouter).addLiquidity(input, pool, minLiquidity, data);
    }

    function migrateFromUniswapV3toTrident(
        IUniswapV3.DecreaseLiquidityParams calldata decreaseLiqParams,
        IUniswapV3.CollectParams calldata collectParams,
        address tridentPool,
        uint256 minLiquidity,
        bytes calldata data
    ) external returns (uint256 liquidity) {
        uniNonfungiblePositionManager.decreaseLiquidity(decreaseLiqParams);
        uniNonfungiblePositionManager.collect(collectParams);

        ITridentRouterMinimal.TokenInput[] memory input = new ITridentRouterMinimal.TokenInput[](2);

        (, , address token0, , , , , , , , , ) = uniNonfungiblePositionManager.positions(decreaseLiqParams.tokenId);
        (, , , address token1, , , , , , , , ) = uniNonfungiblePositionManager.positions(decreaseLiqParams.tokenId);

        input[0].token = token0;
        input[0].native = true;
        input[0].amount = IERC20(token0).balanceOf(address(this));

        input[1].token = token1;
        input[1].native = true;
        input[1].amount = IERC20(token1).balanceOf(address(this));

        liquidity = tridentRouter.addLiquidity(input, tridentPool, minLiquidity, data);
    } */
}

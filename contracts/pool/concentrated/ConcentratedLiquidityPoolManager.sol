// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IMasterDeployer.sol";
import "../../interfaces/IBentoBoxMinimal.sol";
import "../../interfaces/ITridentRouter.sol";
import "../../interfaces/concentratedPool/IConcentratedLiquidityPoolManager.sol";
import "../../interfaces/concentratedPool/IConcentratedLiquidityPool.sol";
import "../../interfaces/concentratedPool/IPositionManager.sol";
import "../../libraries/concentratedPool/FullMath.sol";
import "../../libraries/concentratedPool/TickMath.sol";
import "../../libraries/concentratedPool/DyDxMath.sol";
import "../../utils/TridentBatchable.sol";
import "./TridentNFT.sol";

/// @notice Trident Concentrated Liquidity Pool periphery contract that combines non-fungible position management and staking.
contract ConcentratedLiquidityPoolManager is IConcentratedLiquidityPoolManagerStruct, IPositionManager, TridentNFT, TridentBatchable {
    event IncreaseLiquidity(address indexed pool, address indexed owner, uint256 indexed positionId, uint128 liquidity);
    event DecreaseLiquidity(address indexed pool, address indexed owner, uint256 indexed positionId, uint128 liquidity);

    address internal cachedMsgSender = address(1);
    address internal cachedPool = address(1);

    address internal immutable wETH;
    IBentoBoxMinimal public immutable bento;
    IMasterDeployer public immutable masterDeployer;

    mapping(uint256 => Position) public positions;

    constructor(address _masterDeployer, address _wETH) {
        masterDeployer = IMasterDeployer(_masterDeployer);
        IBentoBoxMinimal _bento = IBentoBoxMinimal(IMasterDeployer(_masterDeployer).bento());
        _bento.registerProtocol();
        bento = _bento;
        wETH = _wETH;
        mint(address(this));
    }

    function mint(
        IConcentratedLiquidityPool pool,
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint128 amount0Desired,
        uint128 amount1Desired,
        bool native,
        uint256 minLiquidity,
        uint256 positionId
    ) external payable returns (uint256 _positionId) {
        require(masterDeployer.pools(address(pool)), "INVALID_POOL");

        cachedMsgSender = msg.sender;
        cachedPool = address(pool);

        uint128 liquidityMinted = uint128(
            pool.mint(
                IConcentratedLiquidityPoolStruct.MintParams({
                    lowerOld: lowerOld,
                    lower: lower,
                    upperOld: upperOld,
                    upper: upper,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    native: native
                })
            )
        );

        require(liquidityMinted >= minLiquidity, "TOO_LITTLE_RECEIVED");

        (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = pool.rangeFeeGrowth(lower, upper);

        if (positionId == 0) {
            // We mint a new NFT.
            _positionId = nftCount.minted;
            positions[_positionId] = Position({
                pool: pool,
                liquidity: liquidityMinted,
                lower: lower,
                upper: upper,
                latestAddition: uint32(block.timestamp),
                feeGrowthInside0: feeGrowthInside0,
                feeGrowthInside1: feeGrowthInside1
            });
            mint(msg.sender);
        } else {
            // We increase liquidity for an existing NFT.
            _positionId = positionId;
            Position storage position = positions[_positionId];
            require(address(position.pool) == address(pool), "POOL_MIS_MATCH");
            require(position.lower == lower && position.upper == upper, "RANGE_MIS_MATCH");
            require(ownerOf(positionId) == msg.sender, "NOT_ID_OWNER");
            // Fees should be claimed first.
            position.feeGrowthInside0 = feeGrowthInside0;
            position.feeGrowthInside1 = feeGrowthInside1;
            position.liquidity += liquidityMinted;
            position.latestAddition = uint32(block.timestamp);
        }

        emit IncreaseLiquidity(address(pool), msg.sender, _positionId, liquidityMinted);

        cachedMsgSender = address(1);
        cachedPool = address(1);
    }

    function mintCallback(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        bool native
    ) external override {
        require(msg.sender == cachedPool, "UNAUTHORIZED_CALLBACK");
        if (native) {
            _depositFromUserToBentoBox(token0, cachedMsgSender, msg.sender, amount0);
            _depositFromUserToBentoBox(token1, cachedMsgSender, msg.sender, amount1);
        } else {
            bento.transfer(token0, cachedMsgSender, msg.sender, amount0);
            bento.transfer(token1, cachedMsgSender, msg.sender, amount1);
        }
        cachedMsgSender = address(1);
        cachedPool = address(1);
    }

    function burn(
        uint256 tokenId,
        uint128 amount,
        address recipient,
        bool unwrapBento
    ) external {
        require(msg.sender == ownerOf(tokenId), "NOT_ID_OWNER");
        Position storage position = positions[tokenId];

        (uint256 token0Fees, uint256 token1Fees, uint256 feeGrowthInside0, uint256 feeGrowthInside1) = positionFees(tokenId);

        address[] memory tokens = position.pool.getAssets();

        uint256 token0Amount;
        uint256 token1Amount;

        if (amount < position.liquidity) {
            (token0Amount, token1Amount, , ) = position.pool.burn(position.lower, position.upper, amount);

            position.feeGrowthInside0 = feeGrowthInside0;
            position.feeGrowthInside1 = feeGrowthInside1;
            position.liquidity -= amount;
        } else {
            (token0Amount, token1Amount, , ) = position.pool.burn(position.lower, position.upper, position.liquidity);

            delete positions[tokenId];
            burn(tokenId);
        }

        unchecked {
            token0Amount += token0Fees;
            token1Amount += token1Fees;
        }

        _transfer(tokens[0], address(this), recipient, token0Amount, unwrapBento);
        _transfer(tokens[1], address(this), recipient, token1Amount, unwrapBento);

        emit DecreaseLiquidity(address(position.pool), msg.sender, tokenId, amount);
    }

    function collect(
        uint256 tokenId,
        address recipient,
        bool unwrapBento
    ) public returns (uint256 token0amount, uint256 token1amount) {
        require(msg.sender == ownerOf(tokenId), "NOT_ID_OWNER");
        Position storage position = positions[tokenId];

        address[] memory tokens = position.pool.getAssets();
        address token0 = tokens[0];
        address token1 = tokens[1];

        (token0amount, token1amount, position.feeGrowthInside0, position.feeGrowthInside1) = positionFees(tokenId);

        uint256 balance0 = bento.balanceOf(token0, address(this));
        uint256 balance1 = bento.balanceOf(token1, address(this));

        if (balance0 < token0amount || balance1 < token1amount) {
            (uint256 amount0fees, uint256 amount1fees) = position.pool.collect(position.lower, position.upper);

            uint256 newBalance0 = amount0fees + balance0;
            uint256 newBalance1 = amount1fees + balance1;

            // Rounding errors due to frequent claiming of other users in the same position may cost us some wei units.
            if (token0amount > newBalance0) token0amount = newBalance0;
            if (token1amount > newBalance1) token1amount = newBalance1;
        }

        _transfer(token0, address(this), recipient, token0amount, unwrapBento);
        _transfer(token1, address(this), recipient, token1amount, unwrapBento);
    }

    /// @notice Returns the claimable fees and the fee growth accumulators of a given position.
    function positionFees(uint256 tokenId)
        public
        view
        returns (
            uint256 token0amount,
            uint256 token1amount,
            uint256 feeGrowthInside0,
            uint256 feeGrowthInside1
        )
    {
        Position memory position = positions[tokenId];

        (feeGrowthInside0, feeGrowthInside1) = position.pool.rangeFeeGrowth(position.lower, position.upper);

        token0amount = FullMath.mulDiv(
            feeGrowthInside0 - position.feeGrowthInside0,
            position.liquidity,
            0x100000000000000000000000000000000
        );

        token1amount = FullMath.mulDiv(
            feeGrowthInside1 - position.feeGrowthInside1,
            position.liquidity,
            0x100000000000000000000000000000000
        );
    }

    function _transfer(
        address token,
        address from,
        address to,
        uint256 shares,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token, from, to, 0, shares);
        } else {
            bento.transfer(token, from, to, shares);
        }
    }

    function _depositFromUserToBentoBox(
        address token,
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        if (token == wETH && address(this).balance > 0) {
            uint256 ethAmount = bento.toAmount(token, amount, true);
            if (ethAmount >= address(this).balance) {
                bento.deposit{value: ethAmount}(address(0), sender, recipient, 0, amount);
                return;
            }
        }
        bento.deposit(token, sender, recipient, 0, amount);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/concentratedPool/IConcentratedLiquidityPoolManager.sol";
import "../../interfaces/concentratedPool/IPositionManager.sol";
import "../../interfaces/IMasterDeployer.sol";
import "../../interfaces/IBentoBoxMinimal.sol";
import "../../interfaces/ITridentRouter.sol";
import "../../libraries/concentratedPool/FullMath.sol";
import "../../libraries/concentratedPool/TickMath.sol";
import "../../libraries/concentratedPool/DyDxMath.sol";
import "../../utils/TridentBatchable.sol";
import "./TridentNFT.sol";
import "hardhat/console.sol";

/// @notice Trident Concentrated Liquidity Pool periphery contract that combines non-fungible position management and staking.
contract ConcentratedLiquidityPoolManager is IPositionManager, IConcentratedLiquidityPoolManagerStruct, TridentNFT, TridentBatchable {
    event IncreaseLiquidity(address indexed pool, address indexed owner, uint256 indexed positionId, uint128 liquidity);
    event DecreaseLiquidity(address indexed pool, address indexed owner, uint256 indexed positionId, uint128 liquidity);

    IBentoBoxMinimal public immutable bento;
    IMasterDeployer public immutable masterDeployer;

    mapping(uint256 => Position) public positions;

    constructor(address _masterDeployer) {
        masterDeployer = IMasterDeployer(_masterDeployer);
        IBentoBoxMinimal _bento = IBentoBoxMinimal(IMasterDeployer(_masterDeployer).bento());
        _bento.registerProtocol();
        bento = _bento;
        _mint(address(0));
    }

    function positionMintCallback(
        address recipient,
        int24 lower,
        int24 upper,
        uint128 amount,
        uint256 feeGrowthInside0,
        uint256 feeGrowthInside1,
        uint256 _positionId
    ) external override returns (uint256 positionId) {
        require(IMasterDeployer(masterDeployer).pools(msg.sender), "NOT_POOL");

        if (_positionId == 0) {
            // We mint a new NFT.
            positions[totalSupply] = Position({
                pool: IConcentratedLiquidityPool(msg.sender),
                liquidity: amount,
                lower: lower,
                upper: upper,
                latestAddition: uint32(block.timestamp),
                feeGrowthInside0: feeGrowthInside0,
                feeGrowthInside1: feeGrowthInside1
            });
            positionId = totalSupply;
            _mint(recipient);
            emit IncreaseLiquidity(msg.sender, recipient, positionId, amount);
        } else if (amount > 0) {
            // We increase liquidity for an existing NFT.
            Position storage position = positions[_positionId];
            require(_positionId < totalSupply, "INVALID_POSITION");
            require(position.lower == lower && position.upper == upper, "RANGE_MIS_MATCH");
            require(position.feeGrowthInside0 == feeGrowthInside0 && position.feeGrowthInside1 == feeGrowthInside1, "UNCLAIMED");
            position.liquidity += amount;
            position.latestAddition = uint32(block.timestamp);
            emit IncreaseLiquidity(msg.sender, recipient, positionId, amount);
        }
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 amount,
        address recipient,
        bool unwrapBento
    ) external {
        require(msg.sender == ownerOf[tokenId], "NOT_ID_OWNER");
        Position storage position = positions[tokenId];

        IPool.TokenAmount[] memory withdrawAmounts;
        IPool.TokenAmount[] memory feeAmounts;
        uint256 oldLiquidity;

        if (amount < position.liquidity) {
            console.log("oke");
            (withdrawAmounts, feeAmounts, oldLiquidity) = position.pool.decreaseLiquidity(
                position.lower,
                position.upper,
                amount,
                address(this),
                false
            );

            (position.feeGrowthInside0, position.feeGrowthInside1) = position.pool.rangeFeeGrowth(position.lower, position.upper);

            position.liquidity -= amount;
        } else {
            (withdrawAmounts, feeAmounts, oldLiquidity) = position.pool.decreaseLiquidity(
                position.lower,
                position.upper,
                position.liquidity,
                address(this),
                false
            );

            delete positions[tokenId];

            _burn(tokenId);
        }

        uint256 token0Amount = withdrawAmounts[0].amount + ((feeAmounts[0].amount * amount) / oldLiquidity);
        uint256 token1Amount = withdrawAmounts[1].amount + ((feeAmounts[1].amount * amount) / oldLiquidity);

        _transfer(withdrawAmounts[0].token, address(this), recipient, token0Amount, unwrapBento);
        _transfer(withdrawAmounts[1].token, address(this), recipient, token1Amount, unwrapBento);

        emit DecreaseLiquidity(address(position.pool), msg.sender, tokenId, amount);
    }

    function collect(
        uint256 tokenId,
        address recipient,
        bool unwrapBento
    ) public returns (uint256 token0amount, uint256 token1amount) {
        Position storage position = positions[tokenId];

        address[] memory tokens = position.pool.getAssets();
        address token0 = tokens[0];
        address token1 = tokens[1];

        (token0amount, token1amount, position.feeGrowthInside0, position.feeGrowthInside1) = positionFees(tokenId);

        uint256 balance0 = bento.balanceOf(token0, address(this));
        uint256 balance1 = bento.balanceOf(token1, address(this));

        if (balance0 < token0amount || balance1 < token1amount) {
            (uint256 amount0fees, uint256 amount1fees) = position.pool.collect(position.lower, position.upper, address(this), false);

            uint256 newBalance0 = amount0fees + balance0;
            uint256 newBalance1 = amount1fees + balance1;

            /// @dev Rounding errors due to frequent claiming of other users in the same position may cost us some wei units
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
}

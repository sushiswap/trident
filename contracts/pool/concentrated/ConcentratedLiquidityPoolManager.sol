// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IPool.sol";
import "./TridentNFT.sol";

interface IConcentratedLiquidityPool is IPool {
    function feeGrowthGlobal0() external view returns (uint256);

    function rangeFeeGrowth(int24 lowerTick, int24 upperTick) external view returns (uint256, uint256);
}

/// @dev combines the nonfungible position manager and the staking contract in one
contract ConcentratedLiquidityPoolManager is TridentNFT {
    struct Position {
        IConcentratedLiquidityPool pool;
        int24 lower;
        int24 upper;
        uint128 liquidity;
        address owner;
        uint32 createdAt;
    }

    uint256 public positionCount;

    mapping(uint256 => Position) public positions; // nft id

    struct Incentive {
        uint256 feeGrowthStart; /// 1m usdc
        uint256 feeGrowthEnd; /// 2m usdc
        uint256 totalFeeGrowthClaimed; /// 0 to current growth
        uint256 totalRewardUnclaimed; /// reward 100k sushi
        uint32 expiry;
        address owner;
    }

    struct Stake {
        uint256 feeGrowthLast;
        uint256 liquidity;
        uint32 createdAt;
    }

    mapping(IConcentratedLiquidityPool => uint256) public incentiveCount;

    mapping(IConcentratedLiquidityPool => mapping(uint256 => Incentive)) public incentives;

    mapping(uint256 => mapping(uint256 => Stake)) public stakes; // stakes[positionId][incentiveId]

    function addIncentive(IConcentratedLiquidityPool pool, Incentive memory incentive) public {
        uint256 current = pool.feeGrowthGlobal0();
        require(current <= incentive.feeGrowthStart, "");
        require(current <= incentive.feeGrowthEnd, "");
        require(incentive.feeGrowthStart < incentive.feeGrowthEnd, "");
        require(incentive.totalRewardUnclaimed > 0, "");
        incentives[pool][incentiveCount[pool]++] = incentive;
        // transfer incentive in
    }

    function reclaimIncentive(
        IConcentratedLiquidityPool pool,
        uint256 incentiveId,
        uint256 amount,
        address receiver
    ) public {
        Incentive storage incentive = incentives[pool][incentiveId];
        require(incentive.owner == msg.sender, "");
        require(incentive.expiry < block.number, "");
        require(incentive.totalRewardUnclaimed >= amount, "");
        // transfer incentive out
    }

    // "subscribe" to the incentive
    function subscribe(uint256 positionId, uint256 incentiveId) public {
        Position storage position = positions[positionId];
        require(incentiveId <= incentiveCount[position.pool], "");
        require(position.owner == msg.sender, "");
        require(position.createdAt < block.number && position.upper - position.lower > 100, ""); // 🤔 get rid of this probs
        (uint256 feeGrowth0, ) = position.pool.rangeFeeGrowth(position.lower, position.upper);
        stakes[positionId][incentiveId] = Stake(feeGrowth0, position.liquidity, uint32(block.number));
    }

    function claimReward(uint256 incentiveId, uint256 positionId) public {
        Position storage position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        Incentive storage incentive = incentives[pool][positionId];
        Stake storage stake = stakes[positionId][incentiveId];
        uint256 currentFeeGrowth = pool.feeGrowthGlobal0();
        if (currentFeeGrowth < incentive.feeGrowthStart || position.owner != msg.sender) return; // after incentive anyone should be able to claim

        uint256 maxFeeGrowth = currentFeeGrowth > incentive.feeGrowthEnd ? currentFeeGrowth : incentive.feeGrowthEnd; // import and use Math.max library

        uint256 feeGrowthUnclaimed = maxFeeGrowth - incentive.totalFeeGrowthClaimed;

        (uint256 feeGrowthLatest, ) = pool.rangeFeeGrowth(position.lower, position.upper);

        uint256 rewards = (incentive.totalRewardUnclaimed * (feeGrowthLatest - stake.feeGrowthLast)) /
            feeGrowthUnclaimed;

        incentive.totalRewardUnclaimed -= rewards;

        incentive.totalFeeGrowthClaimed += 0;

        // transfer rewards
    }

    function mint(IConcentratedLiquidityPool pool, bytes memory mintData) public {
        (, int24 lower, , int24 upper, uint128 amount, address recipient) = abi.decode(
            mintData,
            (int24, int24, int24, int24, uint128, address)
        );

        pool.mint(mintData);

        positions[positionCount++] = Position(pool, lower, upper, amount, recipient, uint32(block.number));
        // @dev Mint Position NFT.
        _mint(recipient);
    }

    function burn(
        IPool pool,
        bytes memory burnData,
        uint256 tokenId
    ) public {
        (int24 lower, int24 upper, uint128 amount, address recipient, bool unwrapBento) = abi.decode(
            burnData,
            (int24, int24, uint128, address, bool)
        );

        pool.burn(burnData);
        // TO-DO update position locally.... 🏄
        // @dev Burn Position NFT.
        _burn(tokenId);
    }

    // transfers the funds
    function mintCallback() external {}
}

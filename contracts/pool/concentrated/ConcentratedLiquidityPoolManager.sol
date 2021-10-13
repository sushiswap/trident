// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IConcentratedLiquidityPool.sol";
import "./ConcentratedLiquidityPosition.sol";
import "../../libraries/concentratedPool/Ticks.sol";
import "hardhat/console.sol";

/// @notice Trident Concentrated Liquidity Pool periphery contract that combines non-fungible position management and staking.
contract ConcentratedLiquidityPoolManager is ConcentratedLiquidityPosition {
    event AddIncentive(IConcentratedLiquidityPool indexed pool, uint256 indexed incentiveId, address indexed rewardToken);
    event Subscribe(uint256 indexed positionId, uint256 indexed incentiveId);
    event ClaimReward(uint256 indexed positionId, uint256 indexed incentiveId, address indexed recipient, uint96 amount);
    event ReclaimIncentive(IConcentratedLiquidityPool indexed pool, uint256 indexed incentiveId, uint256 amount);

    struct Incentive {
        address owner;
        address token;
        uint32 startTime;
        uint32 endTime;
        uint32 expiry;
        uint160 secondsClaimed; // @dev x128.
        uint96 rewardsUnclaimed;
    }

    struct Stake {
        uint160 secondsGrowthInsideLast; // @dev x128.
        bool initialized;
    }

    mapping(IConcentratedLiquidityPool => uint256) public incentiveCount;
    mapping(IConcentratedLiquidityPool => mapping(uint256 => Incentive)) public incentives;
    /// @dev When subscribing to an incentive we take a snapshot of the position secondsGrowth accumulator.
    /// @dev positionId to incentiveId to position's secondsGrowth snapshot mapping.
    mapping(uint256 => mapping(uint256 => Stake)) public stakes;

    constructor(address _masterDeployer) ConcentratedLiquidityPosition(_masterDeployer) {}

    function addIncentive(IConcentratedLiquidityPool pool, Incentive memory incentive) public {
        uint32 current = uint32(block.timestamp);
        require(current <= incentive.startTime, "ALREADY_STARTED");
        require(incentive.startTime < incentive.endTime, "START_PAST_END");
        require(incentive.endTime + 90 days < incentive.expiry, "END_PAST_BUFFER");
        require(incentive.rewardsUnclaimed != 0, "NO_REWARDS");
        incentive.secondsClaimed = 0;
        incentives[pool][incentiveCount[pool]++] = incentive;
        _transfer(incentive.token, msg.sender, address(this), incentive.rewardsUnclaimed, false);
        emit AddIncentive(pool, incentiveCount[pool], incentive.token);
    }

    /// @dev Withdraws any unclaimed incentive rewards.
    function reclaimIncentive(
        IConcentratedLiquidityPool pool,
        uint256 incentiveId,
        address receiver,
        uint96 amount,
        bool unwrapBento
    ) public {
        Incentive storage incentive = incentives[pool][incentiveId];
        require(incentive.owner == msg.sender, "NOT_OWNER");
        require(incentive.expiry < block.timestamp, "EXPIRED");
        require(incentive.rewardsUnclaimed >= amount, "ALREADY_CLAIMED");
        incentive.rewardsUnclaimed -= uint96(amount);
        _transfer(incentive.token, address(this), receiver, amount, unwrapBento);
        emit ReclaimIncentive(pool, incentiveId, amount);
    }

    /// @dev Subscribes a non-fungible position token to an incentive.
    function subscribe(uint256 positionId, uint256[] calldata incentiveId) external {
        require(ownerOf[positionId] == msg.sender, "OWNER");
        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        require(position.liquidity != 0, "INACTIVE");
        Stake memory stakeData = Stake(uint160(rangeSecondsInside(pool, position.lower, position.upper)), true);
        for (uint256 i; i < incentiveId.length; i++) {
            Incentive memory incentive = incentives[pool][incentiveId[i]];
            Stake storage stake = stakes[positionId][incentiveId[i]];
            require(stake.secondsGrowthInsideLast == 0, "SUBSCRIBED");
            require(block.timestamp >= incentive.startTime && block.timestamp < incentive.endTime, "INACTIVE_INCENTIVE");
            stakes[positionId][incentiveId[i]] = stakeData;
            emit Subscribe(positionId, incentiveId[i]);
        }
    }

    function claimRewards(
        uint256 positionId,
        uint256[] memory incentiveIds,
        address recipient,
        bool unwrapBento
    ) public {
        require(ownerOf[positionId] == msg.sender, "OWNER");

        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;

        uint256 currentSecondsGrowth = rangeSecondsInside(pool, position.lower, position.upper);

        for (uint256 i = 0; i < incentiveIds.length; i++) {
            Incentive storage incentive = incentives[pool][incentiveIds[i]];
            Stake storage stake = stakes[positionId][incentiveIds[i]];

            require(stake.initialized, "UNINITIALIZED");

            uint256 rewards;
            uint256 secondsInside;

            {
                uint256 secondsGrowth = currentSecondsGrowth - stake.secondsGrowthInsideLast;
                uint256 maxTime = block.timestamp < incentive.endTime ? incentive.endTime : block.timestamp;
                uint256 secondsUnclaimed = ((maxTime - incentive.startTime) << 128) - incentive.secondsClaimed;
                secondsInside = secondsGrowth * position.liquidity; // secondsGrowth is multiplied by 2**128
                rewards = (incentive.rewardsUnclaimed * secondsInside) / secondsUnclaimed; // 2**128 cancels out
            }

            stake.secondsGrowthInsideLast = uint160(currentSecondsGrowth);
            incentive.secondsClaimed += uint160(secondsInside);
            incentive.rewardsUnclaimed -= uint96(rewards);

            _transfer(incentive.token, address(this), recipient, rewards, unwrapBento);

            emit ClaimReward(positionId, incentiveIds[i], recipient, uint96(rewards));
        }
    }

    function getReward(uint256 positionId, uint256 incentiveId) public view returns (uint256 rewards, uint256 secondsInside) {
        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        Incentive memory incentive = incentives[pool][positionId];
        Stake memory stake = stakes[positionId][incentiveId];
        if (stake.initialized) {
            uint256 secondsGrowth = rangeSecondsInside(pool, position.lower, position.upper) - stake.secondsGrowthInsideLast;
            secondsInside = secondsGrowth * position.liquidity;
            uint256 maxTime = block.timestamp < incentive.endTime ? incentive.endTime : block.timestamp;
            uint256 secondsUnclaimed = ((maxTime - incentive.startTime) << 128) - incentive.secondsClaimed;
            rewards = (incentive.rewardsUnclaimed * secondsInside) / secondsUnclaimed;
        }
    }

    /// @dev Calculates the "seconds per liquidity" accumulator for a range.
    function rangeSecondsInside(
        IConcentratedLiquidityPool pool,
        int24 lowerTick,
        int24 upperTick
    ) public view returns (uint256 secondsInside) {
        (, int24 currentTick) = pool.getPriceAndNearestTicks();

        Ticks.Tick memory lower = pool.ticks(lowerTick);
        Ticks.Tick memory upper = pool.ticks(upperTick);

        (uint256 secondsGrowthGlobal, ) = pool.getSecondsGrowthAndLastObservation();
        uint256 secondsBelow;
        uint256 secondsAbove;

        if (lowerTick <= currentTick) {
            secondsBelow = lower.secondsGrowthOutside;
        } else {
            secondsBelow = secondsGrowthGlobal - lower.secondsGrowthOutside;
        }

        if (currentTick < upperTick) {
            secondsAbove = upper.secondsGrowthOutside;
        } else {
            secondsAbove = secondsGrowthGlobal - upper.secondsGrowthOutside;
        }

        secondsInside = secondsGrowthGlobal - secondsBelow - secondsAbove;
    }
}

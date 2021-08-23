// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IPool.sol";
import "../../interfaces/IBentoBoxMinimal.sol";
import "./TridentNFT.sol";

interface IConcentratedLiquidityPool is IPool {
    function feeGrowthGlobal0() external view returns (uint256);

    function rangeSecondsInside(int24 lowerTick, int24 upperTick) external view returns (uint256);
}

/// @dev combines the nonfungible position manager and the staking contract in one
contract ConcentratedLiquidityPoolManager is TridentNFT {
    // TODO add events
    struct Position {
        IConcentratedLiquidityPool pool;
        uint128 liquidity;
        int24 lower;
        int24 upper;
    }

    struct Incentive {
        address owner;
        address token;
        uint256 rewardsUnclaimed;
        uint160 secondsClaimed; // x128
        uint32 startTime;
        uint32 endTime;
        uint32 expiry;
    }

    struct Stake {
        uint160 secondsInsideLast; // x128
        uint8 initialized;
    }

    mapping(IConcentratedLiquidityPool => uint256) public incentiveCount;

    mapping(IConcentratedLiquidityPool => mapping(uint256 => Incentive)) public incentives;

    mapping(uint256 => Position) public positions;

    mapping(uint256 => mapping(uint256 => Stake)) public stakes;

    IBentoBoxMinimal public immutable bento;

    constructor(IBentoBoxMinimal _bento) {
        bento = _bento;
    }

    function addIncentive(IConcentratedLiquidityPool pool, Incentive memory incentive) public {
        uint32 current = uint32(block.timestamp);
        require(current <= incentive.startTime, "");
        require(current <= incentive.endTime, "");
        require(incentive.startTime < incentive.endTime, "");
        require(incentive.endTime + 5 weeks < incentive.expiry, "");
        require(incentive.rewardsUnclaimed > 0, "");
        incentives[pool][incentiveCount[pool]++] = incentive;
        bento.transfer(incentive.token, msg.sender, address(this), incentive.rewardsUnclaimed);
    }

    /// @notice Withdraws any uncalimed incentive rewards
    function reclaimIncentive(
        IConcentratedLiquidityPool pool,
        uint256 incentiveId,
        uint256 amount,
        address receiver
    ) public {
        Incentive storage incentive = incentives[pool][incentiveId];
        require(incentive.owner == msg.sender, "");
        require(incentive.expiry < uint32(block.timestamp), "");
        require(incentive.rewardsUnclaimed >= amount, "");
        bento.transfer(incentive.token, address(this), receiver, amount);
    }

    // subscribe an nft position to the incentive
    function subscribe(uint256 positionId, uint256 incentiveId) public {
        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        Incentive memory incentive = incentives[pool][positionId];
        Stake storage stake = stakes[positionId][incentiveId];
        require(position.liquidity > 0, "!exsists");
        require(stake.secondsInsideLast == 0, "subscribed");
        require(incentiveId <= incentiveCount[pool], "!incentive");
        require(block.timestamp > incentive.startTime && block.timestamp < incentive.endTime, "");
        stakes[positionId][incentiveId] = Stake(uint160(pool.rangeSecondsInside(position.lower, position.upper)), uint8(1));
    }

    function claimReward(
        uint256 positionId,
        uint256 incentiveId,
        address recipient
    ) public {
        require(ownerOf[positionId] == msg.sender, "");
        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        Incentive storage incentive = incentives[position.pool][positionId];
        Stake storage stake = stakes[positionId][incentiveId];
        require(stake.initialized > 0, "");
        uint256 secondsPerLiquidityInside = pool.rangeSecondsInside(position.lower, position.upper) - stake.secondsInsideLast;
        uint256 secondsInside = secondsPerLiquidityInside * position.liquidity;
        uint256 maxTime = incentive.endTime < block.timestamp ? block.timestamp : incentive.endTime;
        uint256 secondsUnclaimed = (maxTime - incentive.startTime) << (128 - incentive.secondsClaimed);
        uint256 rewards = (incentive.rewardsUnclaimed * secondsInside) / secondsUnclaimed;
        incentive.rewardsUnclaimed -= rewards;
        incentive.secondsClaimed += uint160(secondsInside);
        stake.secondsInsideLast += uint160(secondsPerLiquidityInside);
        bento.transfer(incentive.token, address(this), recipient, rewards);
    }

    function getReward(uint256 positionId, uint256 incentiveId) public view returns (uint256 rewards, uint256 secondsInside) {
        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        Incentive memory incentive = incentives[pool][positionId];
        Stake memory stake = stakes[positionId][incentiveId];
        if (stake.initialized > 0) {
            secondsInside = (pool.rangeSecondsInside(position.lower, position.upper) - stake.secondsInsideLast) * position.liquidity;
            uint256 maxTime = incentive.endTime < block.timestamp ? block.timestamp : incentive.endTime;
            uint256 secondsUnclaimed = (maxTime - incentive.startTime) << (128 - incentive.secondsClaimed);
            rewards = (incentive.rewardsUnclaimed * secondsInside) / secondsUnclaimed;
        }
    }

    function mint(IConcentratedLiquidityPool pool, bytes memory mintData) public {
        (, int24 lower, , int24 upper, uint128 amount, address recipient) = abi.decode(
            mintData,
            (int24, int24, int24, int24, uint128, address)
        );
        pool.mint(mintData);
        positions[totalSupply] = Position(pool, amount, lower, upper);
        /// @dev Mint Position NFT.
        _mint(recipient);
    }

    function burn(
        IPool pool,
        bytes memory burnData,
        uint256 tokenId
    ) public {
        pool.burn(burnData);
        // @dev Burn Position NFT.
        _burn(tokenId);
    }

    // TODO transfers the funds
    function mintCallback() external {}
}

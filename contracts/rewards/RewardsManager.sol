// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPool.sol";

/// @notice Manages the rewards for various pools without requiring users to stake LP tokens.
contract RewardsManager {
    /// @notice Info of each Incentivized pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of SUSHI to distribute per block.
    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
    }

    /// @notice Info of each pool.
    mapping(address => PoolInfo) public poolInfo;

    mapping(address => mapping(address => uint256)) public rewardDebt;

    // @TODO CHANGE SO ANYONE CAN CALL, BUT ALSO LET THE POOL CALL
    function claimRewardsFor(address account) external {
        IPool pool = IPool(msg.sender);
        PoolInfo memory info = poolInfo[msg.sender];

        if (block.number <= info.lastRewardBlock) {
            return;
        }

        if (pool.totalSupply == 0) {
            info.lastRewardBlock = block.number;
            return;
        }

        // @TODO UPDATE TO V2 MATH
        uint256 multiplier = getMultiplier(info.lastRewardBlock, block.number);
        uint256 reward = (multiplier * sushiPerBlock() * info.allocPoint) / info.totalAllocPoint;

        info.accPerShare = info.accPerShare + ((reward * 1e12) / pool.totalSupply());

        info.lastRewardBlock = block.number;

        if (pool.balanceOf(account) > 0) {
            rewardToken.transfer(account, unclaimedRewardsFor(account));
        }

        rewardDebt[msg.sender][account] = ((pool.balanceOf(account) * info.accPerShare) / 1e12);
    }

    function unclaimedRewardsFor(address account) public view returns (uint256) {
        return ((balanceOf[account] * accPerShare) / 1e12) - rewardDebt[account];
    }

    function sushiPerBlock() public view returns (uint256 amount) {
        amount = uint256(MASTERCHEF_SUSHI_PER_BLOCK).mul(MASTER_CHEF.poolInfo(MASTER_PID).allocPoint) / MASTER_CHEF.totalAllocPoint();
    }
}

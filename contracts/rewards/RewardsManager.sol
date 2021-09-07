// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPool.sol";

/// @notice Manages the rewards for various pools without requiring users to stake LP tokens.
contract RewardsManager {
    /// @notice Info of each pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of SUSHI to distribute per block.
    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
    }

    /// `rewardDebt` The amount of SUSHI entitled to the user for a specific pool.
    mapping(address => mapping(address => int256)) public rewardDebt;

    mapping(address => PoolInfo) public poolInfo;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 private constant MASTERCHEF_SUSHI_PER_BLOCK = 1e20;
    uint256 private constant ACC_SUSHI_PRECISION = 1e12;

    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);

    function claimRewardsFor(IPool pool, address account) external {
        PoolInfo memory info = updatePool(pool);

        uint256 debt = rewardDebt[pool][account];
        uint256 amount = pool.balanceOf(account);

        int256 accumulatedSushi = int256(amount.mul(info.accSushiPerShare) / ACC_SUSHI_PRECISION);
        uint256 _pendingSushi = accumulatedSushi.sub(debt).toUInt256();

        // Effects
        rewardDebt[pool][account] = accumulatedSushi;

        // Interactions
        if (_pendingSushi != 0) {
            SUSHI.safeTransfer(to, _pendingSushi);
        }

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onSushiReward(pid, account, account, _pendingSushi, amount);
        }

        emit Harvest(account, pid, _pendingSushi);
    }

    /// @notice Update reward variables of the given pool.
    /// @param pool The address of the pool. See `poolInfo`.
    /// @return info Returns the pool that was updated.
    function updatePool(IPool pool) public returns (PoolInfo memory info) {
        info = poolInfo[pool];
        if (block.number > info.lastRewardBlock) {
            uint256 lpSupply = pool.totalSupply();
            if (lpSupply > 0) {
                uint256 blocks = block.number.sub(info.lastRewardBlock);
                uint256 sushiReward = blocks.mul(sushiPerBlock()).mul(info.allocPoint) / totalAllocPoint;
                info.accSushiPerShare = info.accSushiPerShare.add((sushiReward.mul(ACC_SUSHI_PRECISION) / lpSupply).to128());
            }
            info.lastRewardBlock = block.number.to64();
            poolInfo[pool] = info;
            emit LogUpdatePool(pool, info.lastRewardBlock, lpSupply, info.accSushiPerShare);
        }
    }
}

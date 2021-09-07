// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPool.sol";
import "../interfaces/IRewarder.sol";
import "../interfaces/IMasterChef.sol";

interface Sushi {
    function safeTransfer(address, uint256) external returns (bool);
}

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

    /// @notice Address of MCV1 contract.
    IMasterChef public immutable MASTER_CHEF;

    /// @notice Address of SUSHI contract.
    Sushi public immutable SUSHI;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 private constant MASTERCHEF_SUSHI_PER_BLOCK = 1e20;
    uint256 private constant ACC_SUSHI_PRECISION = 1e12;

    /// `rewardDebt` The amount of SUSHI entitled to the user for a specific pool.
    mapping(address => mapping(address => int256)) public rewardDebt;

    mapping(address => PoolInfo) public poolInfo;

    mapping(address => IRewarder) public rewarder;

    event Harvest(address indexed user, address indexed pid, uint256 amount);
    event LogUpdatePool(address indexed pid, uint64 lastRewardBlock, uint256 lpSupply, uint256 accSushiPerShare);

    constructor(IMasterChef _MASTER_CHEF, Sushi _SUSHI) {
        MASTER_CHEF = _MASTER_CHEF;
        SUSHI = _SUSHI;
    }

    function claimRewardsFor(IPool pool, address account) external {
        PoolInfo memory info = updatePool(pool);

        int256 debt = rewardDebt[address(pool)][account];
        uint256 amount = IERC20(address(pool)).balanceOf(account);

        int256 accumulatedSushi = int256((amount * info.accSushiPerShare) / ACC_SUSHI_PRECISION);
        uint256 _pendingSushi = uint256(accumulatedSushi - debt);

        // Effects
        rewardDebt[address(pool)][account] = accumulatedSushi;

        // Interactions
        if (_pendingSushi != 0) {
            SUSHI.safeTransfer(account, _pendingSushi);
        }

        IRewarder _rewarder = rewarder[address(pool)];
        if (address(_rewarder) != address(0)) {
            _rewarder.onSushiReward(address(pool), account, account, _pendingSushi, amount);
        }

        emit Harvest(account, address(pool), _pendingSushi);
    }

    /// @notice Update reward variables of the given pool.
    /// @param pool The address of the pool. See `poolInfo`.
    /// @return info Returns the pool that was updated.
    function updatePool(IPool pool) public returns (PoolInfo memory info) {
        info = poolInfo[address(pool)];
        if (block.number > info.lastRewardBlock) {
            uint256 lpSupply = IERC20(address(pool)).totalSupply();
            if (lpSupply > 0) {
                uint256 blocks = block.number - info.lastRewardBlock;
                uint256 sushiReward = (blocks * MASTER_CHEF.sushiPerBlock() * info.allocPoint) / totalAllocPoint;
                info.accSushiPerShare = info.accSushiPerShare + uint128((sushiReward * ACC_SUSHI_PRECISION) / lpSupply);
            }
            info.lastRewardBlock = uint64(block.number);
            poolInfo[address(pool)] = info;
            emit LogUpdatePool(address(pool), info.lastRewardBlock, lpSupply, info.accSushiPerShare);
        }
    }
}

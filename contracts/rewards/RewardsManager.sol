// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPool.sol";
import "../interfaces/IRewarder.sol";
import "../interfaces/IMasterChef.sol";
import "../utils/TridentOwnable.sol";

interface Sushi {
    function safeTransfer(address, uint256) external returns (bool);
}

/// @notice Manages the rewards for various pools without requiring users to stake LP tokens.
contract RewardsManager is TridentOwnable {
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
    event LogSetPool(address indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);

    constructor(IMasterChef _MASTER_CHEF, Sushi _SUSHI) {
        MASTER_CHEF = _MASTER_CHEF;
        SUSHI = _SUSHI;
    }

    /// @notice Update the given pool's SUSHI allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(
        address _pool,
        uint256 _allocPoint,
        IRewarder _rewarder,
        bool overwrite
    ) public onlyOwner {
        totalAllocPoint = (totalAllocPoint - poolInfo[_pool].allocPoint) + _allocPoint;
        poolInfo[_pool].allocPoint = uint64(_allocPoint);
        if (overwrite) {
            rewarder[_pool] = _rewarder;
        }
        emit LogSetPool(_pool, _allocPoint, overwrite ? _rewarder : rewarder[_pool], overwrite);
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pools Pool addresses of all to be updated. Make sure to update all active pools.
    function massUpdatePools(IPool[] calldata pools) external {
        uint256 len = pools.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pools[i]);
        }
    }

    /// @notice Harvest rewards for a specific account for a given pool.
    /// @param pool The address of the pool. See `poolInfo`.
    /// @param account The account to claim for.
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

// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinHelpers.sol";
import "./interfaces/IMasterChefV2.sol";
import "./interfaces/IMirinTwapOracle.sol";

contract MirinYieldRebalancer is MirinHelpers {
    struct Checkpoint {
        uint128 fromBlock;
        uint128 value;
    }

    struct Reward {
        uint128 block;
        uint128 amount;
        uint256 lpSupply;
    }

    IMasterChefV2 public immutable masterChef;
    IERC20 public immutable sushi;
    IMirinTwapOracle public immutable oracle;

    uint256 public lastSushiBalance;
    mapping(uint256 => Reward[]) public rewards;
    mapping(uint256 => mapping(address => uint256)) public lastRewardReceived;

    mapping(uint256 => mapping(address => Checkpoint[])) private _lpBalances;

    event Deposit(uint256 indexed pid, uint256 amount, address indexed owner);
    event Withdraw(uint256 indexed pid, uint256 amount, address indexed owner);
    event ClaimReward(uint256 indexed pid, uint256 amount, address indexed owner);
    event Rebalance(uint256 indexed fromPid, uint256 fromAmount, uint256 indexed toPid, uint256 toAmount);

    modifier onlyWETHPool(uint256 pid) {
        IMirinPool pool = IMirinPool(masterChef.lpToken(pid));
        (address token0, address token1) = (pool.token0(), pool.token1());
        require(token0 == weth || token1 == weth, "MIRIN: INVALID_POOL");
        _;
    }

    constructor(
        IMasterChefV2 _masterChef,
        IERC20 _sushi,
        IMirinTwapOracle _oracle,
        address _factory,
        address _legacyFactory,
        address _weth
    ) MirinHelpers(_factory, _legacyFactory, _weth) {
        masterChef = _masterChef;
        sushi = _sushi;
        oracle = _oracle;
    }

    function pendingSushi(uint256 pid, address owner) external view returns (uint256 amount) {
        for (uint256 i = lastRewardReceived[pid][owner]; i < rewards[pid].length; i++) {
            Reward storage reward = rewards[pid][i];
            uint256 lpBalance = _valueAt(_lpBalances[pid][owner], reward.block);
            amount += (reward.amount * lpBalance) / reward.lpSupply;
        }
    }

    function deposit(uint256 pid, uint256 amount) external onlyWETHPool(pid) {
        require(amount > 0, "MIRIN: INVALID_AMOUNT");

        Checkpoint[] storage checkpoints = _lpBalances[pid][msg.sender];
        _updateValueAtNow(checkpoints, _latestValue(checkpoints) + amount);

        address lpToken = masterChef.lpToken(pid);
        _safeTransferFrom(lpToken, msg.sender, address(this), amount);
        IERC20(lpToken).approve(address(masterChef), amount);
        masterChef.deposit(pid, amount, address(this));

        emit Deposit(pid, amount, msg.sender);
    }

    function withdraw(uint256 pid, uint256 amount) external onlyWETHPool(pid) {
        require(amount > 0, "MIRIN: INVALID_AMOUNT");

        Checkpoint[] storage checkpoints = _lpBalances[pid][msg.sender];
        _updateValueAtNow(checkpoints, _latestValue(checkpoints) - amount);

        uint256 lpSupply = masterChef.userInfo(pid, address(this)).amount;
        masterChef.withdraw(pid, amount, msg.sender);
        masterChef.harvest(pid, address(this));

        uint256 sushiBalance = sushi.balanceOf(address(this));
        rewards[pid].push(Reward(uint128(block.number), uint128(sushiBalance - lastSushiBalance), lpSupply));

        claimReward(pid);

        emit Withdraw(pid, amount, msg.sender);
    }

    function rebalance(
        uint256 fromPid,
        uint256 fromAmount,
        uint256 toPid,
        uint256 toAmountMin
    ) external {
        (address fromPool, address fromToken, uint256 fromReward) =
            _poolReward(fromPid, fromAmount, masterChef.poolInfo(fromPid).allocPoint);
        (address toPool, address toToken, uint256 toReward) =
            _poolReward(toPid, toAmountMin, masterChef.poolInfo(toPid).allocPoint);
        require(fromReward > toReward, "MIRIN: DEFICIT");

        _swapPoolToPool(fromPool, fromToken, fromAmount, toPool, toToken, toAmountMin);
        // TODO: check toAmountMin
        // TODO: emit event
    }

    function _swapPoolToPool(
        address fromPool,
        address fromToken,
        uint256 fromAmount,
        address toPool,
        address toToken,
        uint256 toAmountMin
    ) internal {
        _safeTransfer(fromPool, fromPool, fromAmount);
        (uint256 amount0, uint256 amount1) = IMirinPool(fromPool).burn(address(this));
        if (weth == IMirinPool(fromPool).token0()) {
            _safeTransfer(fromToken, fromPool, amount1);
            IMirinPool(fromPool).swap(0, amount1, toPool, bytes(""));
            // TODO: swap to toPool tokens
        } else {
            _safeTransfer(fromToken, fromPool, amount1);
            IMirinPool(fromPool).swap(amount0, 0, toPool, bytes(""));
            // TODO: swap to toPool tokens
        }
    }

    function claimReward(uint256 pid) public {
        uint256 amountReceived;
        uint256 toIndex = rewards[pid].length;
        for (uint256 i = lastRewardReceived[pid][msg.sender]; i < toIndex; i++) {
            Reward storage reward = rewards[pid][i];
            uint256 lpBalance = _valueAt(_lpBalances[pid][msg.sender], reward.block);
            uint256 amount = (reward.amount * lpBalance) / reward.lpSupply;
            amountReceived += amount;
        }
        lastRewardReceived[pid][msg.sender] = toIndex;
        lastSushiBalance = sushi.balanceOf(address(this)) - amountReceived;

        _safeTransfer(address(sushi), msg.sender, amountReceived);

        emit ClaimReward(pid, amountReceived, msg.sender);
    }

    function _poolReward(
        uint256 pid,
        uint256 lpAmount,
        uint64 allocPoint
    )
        internal
        returns (
            address,
            address,
            uint256
        )
    {
        (
            address pool,
            address token,
            uint112 tokenReserve,
            uint112 wethReserve,
            uint256 lpSupply,
            uint256 totalSupply
        ) = _poolInfo(pid);
        uint256 reward =
            ((oracle.current(token, tokenReserve, weth) + wethReserve) * lpSupply) / (totalSupply * allocPoint);
        return (pool, token, reward);
    }

    function _poolInfo(uint256 pid)
        internal
        view
        returns (
            address pool,
            address token,
            uint112 tokenReserve,
            uint112 wethReserve,
            uint256 lpSupply,
            uint256 totalSupply
        )
    {
        IMirinPool p = IMirinPool(masterChef.lpToken(pid));
        (address token0, address token1) = (p.token0(), p.token1());
        require(token0 == weth || token1 == weth, "MIRIN: INVALID_POOL");
        (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
        lpSupply = p.balanceOf(address(this));
        totalSupply = p.totalSupply();

        if (token0 == weth) {
            return (address(p), token1, reserve1, reserve0, lpSupply, totalSupply);
        } else {
            return (address(p), token0, reserve0, reserve1, lpSupply, totalSupply);
        }
    }

    function _latestValue(Checkpoint[] storage checkpoints) internal view returns (uint256) {
        if (checkpoints.length == 0) {
            return 0;
        } else {
            return checkpoints[checkpoints.length - 1].value;
        }
    }

    function _valueAt(Checkpoint[] storage checkpoints, uint256 blockNumber) internal view returns (uint256) {
        if (checkpoints.length == 0) return 0;

        // Shortcut for the actual value
        if (blockNumber >= checkpoints[checkpoints.length - 1].fromBlock)
            return checkpoints[checkpoints.length - 1].value;
        if (blockNumber < checkpoints[0].fromBlock) return 0;

        // Binary search of the value in the array
        uint256 min = 0;
        uint256 max = checkpoints.length - 1;
        while (max > min) {
            uint256 mid = (max + min + 1) / 2;
            if (checkpoints[mid].fromBlock <= blockNumber) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return checkpoints[min].value;
    }

    function _updateValueAtNow(Checkpoint[] storage checkpoints, uint256 value) internal {
        if ((checkpoints.length == 0) || (checkpoints[checkpoints.length - 1].fromBlock < block.number)) {
            Checkpoint storage newCheckPoint = checkpoints.push();
            newCheckPoint.fromBlock = uint128(block.number);
            newCheckPoint.value = uint128(value);
        } else {
            Checkpoint storage oldCheckPoint = checkpoints[checkpoints.length - 1];
            oldCheckPoint.value = uint128(value);
        }
    }
}

pragma solidity ^0.8.4;

import "./IndexPool.sol";

interface ERC20 {
    function transfer(address, uint256);
}

/// @notice A pool that simply is an incentivized version of the index pool.
contract IncentivizedPool is IndexPool {

    mapping (address => uint256) public rewardDebt;

    uint256 public rewardPerShare;
    uint256 public rewardPerBlock;

    uint256 public lastRewardBlock;
    uint256 public bonusEndBlock;

    uint256 public allocPoint;
    uint256 public totalAllocPoint;

    uint256 public accPerShare;

    uint256 public constant BONUS_MULTIPLIER = 10;

    ERC20 public rewardToken;

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        if (totalSupply == 0) {
            lastRewardBlock = block.number;
        }

        uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
        uint256 reward = multiplier.mul(rewardPerBlock).mul(allocPoint).div(totalAllocPoint);

        accSushiPerShare = accPerShare.add(reward.mul(1e12).div(totalSupply));

        lastRewardBlock = block.number;

        if (balances[from] > 0) {
            rewardToken.transfer(from, balances[from].mul(accPerShare).div(1e12).sub(rewardDebt));
        }
    }

    function getMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
            bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

}

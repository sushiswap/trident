// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IndexPool.sol";
import "../rewards/RewardsManager.sol";

/// @notice A pool that simply is an incentivized version of the index pool.
contract IncentivizedPool is IndexPool {
    RewardsManager public immutable rewards;

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        rewards.claimRewards(from);
    }
}

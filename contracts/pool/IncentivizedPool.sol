// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IndexPool.sol";
import "../rewards/RewardsManager.sol";

/// @notice A pool that simply is an incentivized version of the index pool.
contract IncentivizedPool is IndexPool {
    RewardsManager public rewards;

    constructor(bytes memory _deployData, address _masterDeployer) IndexPool(_deployData, _masterDeployer) {
        (, , , address _rewards) = abi.decode(_deployData, (address[], uint256[], uint256, address));

        rewards = RewardsManager(_rewards);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (address(rewards) == address(0)) {
            return;
        }

        rewards.claimRewardsFor(this, from);
    }
}

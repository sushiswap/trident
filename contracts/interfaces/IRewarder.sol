// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    function onSushiReward(
        address pool,
        address user,
        address recipient,
        uint256 sushiAmount,
        uint256 newLpAmount
    ) external;

    function pendingTokens(
        address pool,
        address user,
        uint256 sushiAmount
    ) external view returns (IERC20[] memory, uint256[] memory);
}

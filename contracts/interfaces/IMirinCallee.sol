// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

interface IMirinCallee {
    function mirinCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

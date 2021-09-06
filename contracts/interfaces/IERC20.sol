// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

interface IERC20 {
    function approve(address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}

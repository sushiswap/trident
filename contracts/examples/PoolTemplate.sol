// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

/**
 * @author Mudit Gupta
 */
contract PoolTemplate {
    uint256 public immutable configValue;
    address public immutable token0;
    address public immutable token1;

    constructor(bytes memory _data) {
        (token0, token1, configValue) = abi.decode(_data, (address, address, uint256));
    }
}

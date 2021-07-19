// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "../libraries/MirinMath.sol";

contract MirinMathTest {
    function sqrt(uint256 x) public pure returns (uint256) {
        return MirinMath.sqrt(x);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../pool/ConstantProductPool.sol";

abstract contract SqrtMock is ConstantProductPool {
    function checkSqrt(uint256 x) public pure returns (uint256) {
        return ConstantProductPool.sqrt(x);
    }
}

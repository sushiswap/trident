// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../../contracts/libraries/TridentMath.sol";


contract TridentMathWrapper {

    function sqrt(uint256 a) public view returns (uint256) {
        return TridentMath.sqrt(a);
    }
}
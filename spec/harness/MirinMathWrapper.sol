// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../../contracts/libraries/MirinMath.sol";


contract MirinMathWrapper {

    //using MirinMath for MirinMath;
    //MirinMath public mirinMath;

    function sqrt(uint256 a) public view returns (uint256) {
        MirinMath.sqrt(a);
    }
}
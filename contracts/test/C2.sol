// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

contract C2 {
    uint256 public total;

    function increase(uint256 amount) public payable {
        require(amount == msg.value);
        total += msg.value;
    }
}

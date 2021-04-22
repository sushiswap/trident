// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../pool/MirinERC20.sol";

contract ERC20Token is MirinERC20 {
    constructor() {
        mint(msg.sender, 100000);
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}

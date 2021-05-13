// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import "../pool/MirinERC20.sol";

contract ERC20TestToken is MirinERC20 {
    constructor() {
        mint(msg.sender, 1e40);
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}

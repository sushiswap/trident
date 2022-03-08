// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >= 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract ERC20Mock is ERC20Permit {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) ERC20Permit(name) {
        _mint(msg.sender, supply);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "hardhat/console.sol";

contract FlashSwapMock {
    IBentoBoxMinimal public immutable bento;

    constructor(IBentoBoxMinimal _bento) {
        bento = _bento;
    }

    function testFlashSwap(IPool pair, bytes calldata data) external {
        pair.flashSwap(data);
    }

    function tridentSwapCallback(bytes calldata data) external {
        (bool success, address token) = abi.decode(data, (bool, address));
        if (success) {
            IERC20(token).transfer(address(bento), IERC20(token).balanceOf(address(this)));
            bento.deposit(token, address(this), msg.sender, IERC20(token).balanceOf(address(this)), 0);
        }
    }
}

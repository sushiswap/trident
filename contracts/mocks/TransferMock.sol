// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >= 0.8.0;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract TransferMock {
    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    function safeApprove(
        address token,
        address to,
        uint256 value
    ) external {
        ERC20(token).safeApprove(to, value);
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) external {
        ERC20(token).safeTransfer(to, value);
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) external {
        ERC20(token).safeTransferFrom(from, to, value);
    }

    function safeTransferETH(address to, uint256 value) external {
        to.safeTransferETH(value);
    }
}

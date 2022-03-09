// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

/// @notice Trident franchised pool whitelist manager interface.
interface IWhiteListManager {
    function whitelistedAccounts(address operator, address account) external returns (bool);
}

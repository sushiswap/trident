// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @author Mudit Gupta
 */
contract PoolProxy is ERC1967Proxy {

    constructor(address _logic, bytes memory _data) payable ERC1967Proxy(_logic, _data) {}

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function upgradeTo(address newImplementation) external {
        if (msg.sender == address(this)) {
            _upgradeTo(newImplementation);
        } else {
            _fallback();
        }
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) external {
        if (msg.sender == address(this)) {
            _upgradeToAndCall(newImplementation, data, forceCall);
        } else {
            _fallback();
        }
    }
}

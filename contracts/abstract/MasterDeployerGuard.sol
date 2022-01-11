// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

error UnauthorisedDeployer();

abstract contract MasterDeployerGuard {
    address public immutable masterDeployer;
    constructor(address _masterDeployer) {
        masterDeployer = _masterDeployer;
    }
    modifier onlyMaster() {
     if (msg.sender != masterDeployer) revert UnauthorisedDeployer();
        _;
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IMasterDeployer.sol";

interface IStablePoolFactory {
    function getDeployData() external view returns (bytes memory, IMasterDeployer);
}

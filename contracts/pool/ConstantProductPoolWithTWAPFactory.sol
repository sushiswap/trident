// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./ConstantProductPoolWithTWAP.sol";
import "./PairPoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Constant Product Pool with configurations and TWAP.
/// @author Mudit Gupta.
contract ConstantProductPoolWithTWAPFactory is PairPoolDeployer {
    constructor(address _masterDeployer) PairPoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, ) = abi.decode(_deployData, (address, address, uint256));
        pool = _deployPool(tokenA, tokenB, type(ConstantProductPoolWithTWAP).creationCode, _deployData);
    }
}
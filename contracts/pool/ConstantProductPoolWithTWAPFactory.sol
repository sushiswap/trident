// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

import "./ConstantProductPoolWithTWAP.sol";
import "./PairPoolDeployer.sol";

/**
 * @author Mudit Gupta
 */
contract ConstantProductPoolWithTWAPFactory is PairPoolDeployer {
    constructor(address _masterDeployer) PairPoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address) {
        (IERC20 tokenA, IERC20 tokenB, ) = abi.decode(_deployData, (IERC20, IERC20, uint256));
        return
            _deployPool(
                address(tokenA),
                address(tokenB),
                abi.encodePacked(
                    type(ConstantProductPoolWithTWAP).creationCode,
                    abi.encode(_deployData, masterDeployer)
                )
            );
    }
}

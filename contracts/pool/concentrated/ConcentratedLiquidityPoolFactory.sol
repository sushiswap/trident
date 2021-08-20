// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./ConcentratedLiquidityPool.sol";
import "../PairPoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Concentrated Liquidity Pool with configurations.
/// @author Mudit Gupta.
contract ConcentratedLiquidityPoolFactory is PairPoolDeployer {
    constructor(address _masterDeployer) PairPoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, uint24 swapFee, uint160 price) = abi.decode(
            _deployData,
            (address, address, uint24, uint160)
        );
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
            _deployData = abi.encode(tokenA, tokenB, swapFee, price);
        }
        pool = _deployPool(tokenA, tokenB, type(ConcentratedLiquidityPool).creationCode, _deployData);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./ConstantProductPool.sol";
import "../../abstract/PoolDeployer.sol";

/// @notice Contract for deploying Trident exchange Constant Product Pool with configurations.
/// @author Mudit Gupta.
contract ConstantProductPoolFactory is PoolDeployer {
    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}

    struct ConstantProductPoolInfo {
        uint8 tokenA;
        uint8 tokenB;
        uint112 reserve0;
        uint112 reserve1;
        uint16 swapFeeAndTwapSupport;
    }

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, uint256 swapFee, bool twapSupport) = abi.decode(_deployData, (address, address, uint256, bool));

        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        // @dev Strips any extra data.
        _deployData = abi.encode(tokenA, tokenB, swapFee, twapSupport);

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        // @dev Salt is not actually needed since `_deployData` is part of creationCode and already contains the salt.
        bytes32 salt = keccak256(_deployData);
        pool = address(new ConstantProductPool{salt: salt}(_deployData, masterDeployer));
        _registerPool(pool, tokens, salt);
    }

    // @dev tokens MUST be sorted i < j => token[i] < token[j]
    // @dev tokens.length < 256
    function getPoolsForTokens(address[] calldata tokens)
        external
        view
        returns (ConstantProductPoolInfo[] memory poolInfos, uint256 length)
    {
        uint8 tokenNumber = uint8(tokens.length);
        for (uint8 i = 0; i < tokenNumber; i++) {
            mapping(address => address[]) storage poolIs = pools[tokens[i]];
            for (uint8 j = i + 1; j < tokenNumber; j++) {
                length += poolIs[tokens[j]].length;
            }
        }
        poolInfos = new ConstantProductPoolInfo[](length);
        uint256 poolNumber = 0;
        for (uint8 i = 0; i < tokenNumber; i++) {
            mapping(address => address[]) storage poolIs = pools[tokens[i]];
            for (uint8 j = i + 1; j < tokenNumber; j++) {
                address[] storage poolIJs = poolIs[tokens[j]];
                for (uint256 k = 0; k < poolIJs.length; k++) {
                    ConstantProductPoolInfo memory poolInfo = poolInfos[poolNumber++];
                    poolInfo.tokenA = i;
                    poolInfo.tokenB = j;
                    ConstantProductPool pool = ConstantProductPool(poolIJs[k]);
                    (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pool.getReserves();
                    poolInfo.reserve0 = reserve0;
                    poolInfo.reserve1 = reserve1;
                    poolInfo.swapFeeAndTwapSupport = uint16(pool.swapFee());
                    if (blockTimestampLast != 0) poolInfo.swapFeeAndTwapSupport += 1 << 15;
                }
            }
        }
    }
}

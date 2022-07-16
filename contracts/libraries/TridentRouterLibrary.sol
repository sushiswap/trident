// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/ITridentRouter.sol";
import "../interfaces/IPool.sol";

library TridentRouterLibrary {
    /// @notice Get Amount In from the pool
    /// @param pool Pool address
    /// @param amountOut Amount out required
    /// @param tokenOut Token out required
    function getAmountIn(
        address pool,
        uint256 amountOut,
        address tokenOut
    ) internal view returns (uint256 amountIn) {
        bytes memory data = abi.encode(tokenOut, amountOut);
        amountIn = IPool(pool).getAmountIn(data);
    }

    /// @notice Get Amount In multihop
    /// @param path Path for the hops (pool addresses)
    /// @param tokenOut Token out required
    /// @param amountOut Amount out required
    function getAmountsIn(
        ITridentRouter.Path[] memory path,
        address tokenOut,
        uint256 amountOut
    ) internal view returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length + 1);
        amounts[amounts.length - 1] = amountOut;

        for (uint256 i = path.length; i > 0; i--) {
            uint256 amountIn = getAmountIn(path[i - 1].pool, amounts[i], tokenOut);
            amounts[i - 1] = amountIn;
            if (i > 1) {
                (tokenOut) = abi.decode(path[i - 1].data, (address));
            }
        }
    }
}

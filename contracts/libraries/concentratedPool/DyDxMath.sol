// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./FullMath.sol";
import "./UnsafeMath.sol";

library DyDxMath {
    function getDx(
        uint256 liquidity,
        uint256 priceLower,
        uint256 priceUpper,
        bool roundUp
    ) internal pure returns(uint256) {
        if (roundUp) {
        return UnsafeMath.divRoundingUp(
            FullMath.mulDivRoundingUp(
                liquidity << 96,
                priceUpper - priceLower,
                priceUpper
            ),
            priceLower
        );
        } else {
            return FullMath.mulDiv(liquidity << 96, priceUpper - priceLower, priceUpper) / priceLower;
        }
    }

    function getDy(
        uint256 liquidity,
        uint256 priceLower,
        uint256 priceUpper,
        bool roundUp
    ) internal pure returns(uint256) {
        if (roundUp) {
            return FullMath.mulDivRoundingUp(liquidity, priceUpper - priceLower, 0x1000000000000000000000000);
        } else {
            return FullMath.mulDiv(liquidity, priceUpper - priceLower, 0x1000000000000000000000000);
        }
    }
}

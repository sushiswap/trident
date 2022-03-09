// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

/// @notice Trident NFT interface.
interface ITridentNFT {
    function ownerOf(uint256) external view returns (address);
}

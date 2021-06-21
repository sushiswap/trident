// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

/// @notice Allows anyone to join SushiSwap pool whitelist if they exist in a merkle root.
interface IMerkleWhitelister {
    // Returns the merkle root of the merkle tree containing accounts available to join list.
    function merkleRoot() external view returns (bytes32);
    // Returns true if the index has been marked claimed.
    function isWhitelisted(uint256 index) external view returns (bool);
    // Claim the given amount of the token to the given address. Reverts if the inputs are invalid.
    function joinWhitelist(uint256 index, address account, bytes32[] calldata merkleProof) external;

    // This event is triggered whenever a {joinWhitelist} call succeeds.
    event Whitelisted(uint256 index, address account);
}

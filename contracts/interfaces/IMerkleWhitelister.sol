// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

/// @notice Allows anyone to join SushiSwap pool whitelist if they exist in a merkle root.
interface IMerkleWhitelister {
    /// @dev Returns the merkle root of the merkle tree containing accounts available to join whitelist.
    function merkleRoot() external view returns (bytes32);
    /// @dev Returns true if the index has been marked claimed.
    function isWhitelisted(uint256 index) external view returns (bool);
    /// @dev Claim spot in whitelist for an account. Reverts if the inputs are invalid.
    function joinWhitelist(uint256 index, address account, bytes32[] calldata merkleProof) external;
    /// @dev This event is triggered whenever a {joinWhitelist} call succeeds.
    event JoinWhitelist(uint256 index, address account);
    /// @dev This event is triggered whenever a {setMerkleRoot} call succeeds.
    event SetMerkleRoot(bytes32 merkleRoot); 
}

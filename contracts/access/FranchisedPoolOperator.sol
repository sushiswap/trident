// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../interfaces/IMerkleWhitelister.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @notice Allows anyone to set and manage SushiSwap pool whitelisting.
contract FranchisedPoolOperator is IMerkleWhitelister {
    MerkleRoot[] public rootInfo;
    
    function merkleRoot() external override pure returns (bytes32) { return "0x"; }
    function isWhitelisted(uint256 index) external override pure returns (bool) { return false; }
    function joinWhitelist(uint256 index, address account, bytes32[] calldata merkleProof) external override pure { return; }

    struct MerkleRoot {
        address operator;
        bytes32 merkleRoot;
    }
    
    function setMerkleRoot(bytes32 merkleRoot) external override {
        rootInfo.push(MerkleRoot({
            operator: msg.sender,
            merkleRoot: merkleRoot
        }));
        emit SetMerkleRoot(merkleRoot);
    }
    
    function resetMerkleRoot(uint256 rootId, bytes32 newMerkleRoot) external {
        require(msg.sender == rootInfo[rootId].operator, '!operator');
        rootInfo[rootId].merkleRoot = newMerkleRoot;
        emit SetMerkleRoot(newMerkleRoot);
    }
}

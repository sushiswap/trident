// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Contract for managing Trident exchange access control - adapted from boringcrypto/BoringSolidity/blob/master/contracts/BoringOwnable.sol, License-Identifier: MIT.
contract TridentOwnable {
    address public owner;
    address public pendingOwner;

    event TransferOwnership(address indexed from, address indexed to);
    event TransferOwnershipClaim(address indexed from, address indexed to);

    /// @notice Initialize contract and grant deployer account (`msg.sender`) access role.
    constructor() {
        owner = msg.sender;
        emit TransferOwnership(address(0), msg.sender);
    }

    /// @notice Access control modifier that requires modified function to be called by `owner` account.
    modifier onlyOwner() {
        require(msg.sender == owner, "TridentOwnable: NOT_OWNER");
        _;
    }

    /// @notice `pendingOwner` can claim `owner` account.
    function claimOwner() external {
        require(msg.sender == pendingOwner, "TridentOwnable: NOT_PENDING_OWNER");
        emit TransferOwnership(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    /// @notice Transfer `owner` account.
    /// @param recipient Account granted `owner` access control.
    /// @param direct If 'true', ownership is directly transferred.
    function transferOwnership(address recipient, bool direct) external onlyOwner {
        if (direct) {
            owner = recipient;
            emit TransferOwnership(msg.sender, recipient);
        } else {
            pendingOwner = recipient;
            emit TransferOwnershipClaim(msg.sender, recipient);
        }
    }
}

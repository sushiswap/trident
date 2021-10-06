// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident franchised pool whitelist manager.
contract WhiteListManager {
    event WhiteListAccount(address indexed operator, address indexed account, bool approved);
    event SetMerkleRoot(address indexed operator, bytes32 merkleRoot);
    event JoinWithMerkle(address indexed operator, uint256 indexed index, address indexed account);

    /// @notice EIP-712 related variables and functions.
    bytes32 internal constant APPROVAL_SIGNATURE_HASH = keccak256("SetWhitelisting(address account,bool approved,uint256 deadline)");
    bytes32 internal constant DOMAIN_SEPARATOR_SIGNATURE_HASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 internal immutable _DOMAIN_SEPARATOR;
    uint256 internal immutable DOMAIN_SEPARATOR_CHAIN_ID;

    mapping(address => bytes32) public merkleRoot;
    mapping(address => mapping(address => bool)) public whitelistedAccounts;
    mapping(address => mapping(uint256 => uint256)) internal whitelistedBitMap;

    constructor() {
        DOMAIN_SEPARATOR_CHAIN_ID = block.chainid;
        _DOMAIN_SEPARATOR = _calculateDomainSeparator();
    }
    
    function _calculateDomainSeparator() internal view returns (bytes32 domainSeperator) {
        domainSeperator = keccak256(abi.encode(DOMAIN_SEPARATOR_SIGNATURE_HASH, keccak256("WhiteListManager"), block.chainid, address(this)));
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32 domainSeperator) {
        domainSeperator = block.chainid == DOMAIN_SEPARATOR_CHAIN_ID ? _DOMAIN_SEPARATOR : _calculateDomainSeparator();
    }

    function whitelistAccount(address user, bool approved) external {
        _whitelistAccount(msg.sender, user, approved);
    }

    function _whitelistAccount(
        address operator,
        address account,
        bool approved
    ) internal {
        whitelistedAccounts[operator][account] = approved;
        emit WhiteListAccount(operator, account, approved);
    }

    /// @notice Approves or revokes whitelisting for accounts.
    /// @param operator The address of the operator that approves or revokes access.
    /// @param account The address who gains or loses access.
    /// @param approved If 'true', approves access - if 'false', revokes access.
    /// @param deadline The time at which to expire the signature.
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    function setWhitelisting(
        address operator,
        address account,
        bool approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        /// @dev Checks:
        require(account != address(0), "ACCOUNT_NOT_SET");
        // - also, ecrecover returns address(0) on failure. So we check this, even if the modifier should prevent it:
        require(operator != address(0), "OPERATOR_NULL");
        require(deadline >= block.timestamp && deadline <= (block.timestamp + 1 weeks), "EXPIRED");

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(APPROVAL_SIGNATURE_HASH, account, approved, deadline))
            )
        );

        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == operator, "INVALID_SIGNATURE");

        _whitelistAccount(operator, account, approved);
    }

    /// **** WHITELISTING
    /// @dev Adapted from OpenZeppelin utilities and Uniswap merkle distributor.
    function isWhitelisted(address operator, uint256 index) public view returns (bool success) {
        uint256 whitelistedWordIndex = index / 256;
        uint256 whitelistedBitIndex = index % 256;
        uint256 claimedWord = whitelistedBitMap[operator][whitelistedWordIndex];
        uint256 mask = (1 << whitelistedBitIndex);
        success = claimedWord & mask == mask;
    }

    function joinWhitelist(
        address operator,
        uint256 index,
        address account,
        bytes32[] calldata merkleProof
    ) external {
        require(!isWhitelisted(operator, index), "CLAIMED");
        bytes32 node = keccak256(abi.encodePacked(index, account));
        bytes32 computedHash = node;
        for (uint256 i = 0; i < merkleProof.length; i++) {
            bytes32 proofElement = merkleProof[i];
            if (computedHash <= proofElement) {
                /// @dev Hash(current computed hash + current element of the proof).
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                /// @dev Hash(current element of the proof + current computed hash).
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        /// @dev Check if the computed hash (root) is equal to the provided root.
        require(computedHash == merkleRoot[operator], "NOT_ROOTED");
        uint256 whitelistedWordIndex = index / 256;
        uint256 whitelistedBitIndex = index % 256;
        whitelistedBitMap[operator][whitelistedWordIndex] = whitelistedBitMap[operator][whitelistedWordIndex] | (1 << whitelistedBitIndex);
        _whitelistAccount(operator, account, true);
        emit JoinWithMerkle(operator, index, account);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external {
        /// @dev Set the new merkle root.
        merkleRoot[msg.sender] = _merkleRoot;
        emit SetMerkleRoot(msg.sender, _merkleRoot);
    }
}

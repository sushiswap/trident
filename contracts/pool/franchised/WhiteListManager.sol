// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

contract WhiteListManager {
    event LogWhiteListUser(address indexed operator, address indexed user, bool approved);
    event LogSetMerkleRoot(address operator, bytes32 merkleRoot);
    event LogJoinWithMerkle(address operator, uint256 indexed index, address indexed account);

    mapping(address => mapping(address => bool)) public whitelistedUsers;

    // merkle root variables

    mapping(address => bytes32) public merkleRoot;
    /// @dev This is a packed array of booleans.
    mapping(address => mapping(uint256 => uint256)) internal whitelistedBitMap;

    // EIP712 related variables and functions

    bytes32 private constant DOMAIN_SEPARATOR_SIGNATURE_HASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    // See https://eips.ethereum.org/EIPS/eip-191
    string private constant EIP191_PREFIX_FOR_EIP712_STRUCTURED_DATA = "\x19\x01";
    bytes32 private constant APPROVAL_SIGNATURE_HASH = keccak256("SetWhitelisting(address user,bool approved,uint256 deadline)");

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private immutable _DOMAIN_SEPARATOR;
    // solhint-disable-next-line var-name-mixedcase
    uint256 private immutable DOMAIN_SEPARATOR_CHAIN_ID;

    function _calculateDomainSeparator(uint256 chainId) private view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_SIGNATURE_HASH, keccak256("WhiteListManager"), chainId, address(this)));
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId == DOMAIN_SEPARATOR_CHAIN_ID ? _DOMAIN_SEPARATOR : _calculateDomainSeparator(chainId);
    }

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        _DOMAIN_SEPARATOR = _calculateDomainSeparator(DOMAIN_SEPARATOR_CHAIN_ID = chainId);
    }

    function whitelistUser(address user, bool approved) public {
        _whitelistUser(msg.sender, user, approved);
    }

    function _whitelistUser(
        address operator,
        address user,
        bool approved
    ) private {
        whitelistedUsers[operator][user] = approved;
        emit LogWhiteListUser(operator, user, approved);
    }

    /// @notice Approves or revokes whitelisting for users
    /// @param operator The address of the operator that approves or revokes access.
    /// @param user The address who gains or loses access.
    /// @param approved If True approves access. If False revokes access.
    /// @param deadline Time when signature expires to prohibit replays.
    /// @param v Part of the signature. (See EIP-191)
    /// @param r Part of the signature. (See EIP-191)
    /// @param s Part of the signature. (See EIP-191)
    function setWhitelisting(
        address operator,
        address user,
        bool approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        // Checks
        require(user != address(0), "WhiteListMgr: user not set");

        // Also, ecrecover returns address(0) on failure. So we check this, even if the modifier should prevent this:
        require(operator != address(0), "WhiteListMgr: Operator cannot be 0");

        require(deadline >= block.timestamp && deadline <= (block.timestamp + 1 weeks), "WhiteListMgr: EXPIRED");

        bytes32 digest = keccak256(
            abi.encodePacked(
                EIP191_PREFIX_FOR_EIP712_STRUCTURED_DATA,
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(APPROVAL_SIGNATURE_HASH, user, approved, deadline))
            )
        );

        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == operator, "WhiteListMgr: Invalid Signature");

        _whitelistUser(operator, user, approved);
    }

    /// **** WHITELISTING
    // @dev Adapted from OpenZeppelin utilities and Uniswap merkle distributor.
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
    ) public {
        require(!isWhitelisted(operator, index), "CLAIMED");
        bytes32 node = keccak256(abi.encodePacked(index, account));
        bytes32 computedHash = node;
        for (uint256 i = 0; i < merkleProof.length; i++) {
            bytes32 proofElement = merkleProof[i];
            if (computedHash <= proofElement) {
                // @dev Hash(current computed hash + current element of the proof).
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // @dev Hash(current element of the proof + current computed hash).
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        // @dev Check if the computed hash (root) is equal to the provided root.
        require(computedHash == merkleRoot[operator], "NOT_ROOTED");
        uint256 whitelistedWordIndex = index / 256;
        uint256 whitelistedBitIndex = index % 256;
        whitelistedBitMap[operator][whitelistedWordIndex] = whitelistedBitMap[operator][whitelistedWordIndex] | (1 << whitelistedBitIndex);
        _whitelistUser(operator, account, true);
        emit LogJoinWithMerkle(operator, index, account);
    }

    function setMerkleRoot(bytes32 _merkleRoot) public {
        // @dev Set the new merkle root.
        merkleRoot[msg.sender] = _merkleRoot;
        emit LogSetMerkleRoot(msg.sender, _merkleRoot);
    }
}

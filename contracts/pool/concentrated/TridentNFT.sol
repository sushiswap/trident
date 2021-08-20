// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident pool ERC-721 contract.
contract TridentNFT {
    uint256 public totalSupply; // @dev Tracks total liquidity range positions.
    string public constant name = "TridentNFT";
    string public constant symbol = "tNFT";

    mapping(address => uint256) public balanceOf; // @dev Tracks liquidity range positions held by an account.
    mapping(uint256 => address) public getApproved;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => string) public tokenURI;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    event Approval(address indexed approver, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed approver, address indexed operator, bool approved);
    event Transfer(address indexed owner, address indexed recipient, uint256 indexed tokenId);

    function supportsInterface(bytes4 sig) external pure returns (bool) {
        return (sig == 0x80ac58cd || sig == 0x5b5e139f); // @dev ERC-165.
    }

    function approve(address spender, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_APPROVED");
        getApproved[tokenId] = spender;
        emit Approval(msg.sender, spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function _mint(address recipient) internal {
        totalSupply++;
        uint256 tokenId = totalSupply;
        balanceOf[recipient]++;
        ownerOf[tokenId] = recipient;
        emit Transfer(address(0), recipient, tokenId); 
    }

    function _burn(uint256 tokenId) internal {
        totalSupply--;
        balanceOf[msg.sender]--;
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = address(0);
        emit Transfer(msg.sender, address(0), tokenId);
    }
 
    function transfer(address recipient, uint256 tokenId) external {
        require(msg.sender == ownerOf[tokenId], "NOT_OWNER");
        balanceOf[msg.sender]--;
        balanceOf[recipient]++;
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = recipient;
        emit Transfer(msg.sender, recipient, tokenId);
    }

    function transferFrom(
        address,
        address recipient,
        uint256 tokenId
    ) external {
        address owner = ownerOf[tokenId];
        require(
            msg.sender == owner || msg.sender == getApproved[tokenId] || isApprovedForAll[owner][msg.sender],
            "NOT_APPROVED"
        );
        balanceOf[owner]--;
        balanceOf[recipient]++;
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = recipient;
        emit Transfer(owner, recipient, tokenId);
    }
}

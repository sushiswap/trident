// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Contract for Trident Concentrated Liquidity Pool ERC-721 `positions`.
contract TridentNFT {
    uint256 public totalSupply; // @dev Tracks total unique liquidity range positions.
    string constant public name = "Sushi LP Token";
    string constant public symbol = "SLP";
    string constant public baseURI = "";
    
    mapping(address => uint256) public balanceOf; // @dev Tracks liquidity range positions held by an account.
    mapping(uint256 => address) public getApproved;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => string) public tokenURI;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    
    event Approval(address indexed approver, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed approver, address indexed operator, bool approved);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    mapping(int24 => mapping(int24 => Position)) public positions;
    struct Position { // @dev Virtual pool for concentrated liquidity in tick range.
        uint128 liquidity; // last range liquidity 
        uint256 feeGrowthInside0LastX128; // per unit of liquidity
        uint256 feeGrowthInside1LastX128;
        uint256 totalSupply; // total range mint for pool range providers
        mapping(address => uint256) balanceOf; // account provider range mint balance (compare erc20)
    }
    
    mapping(uint256 => Range) public ranges; // @dev Tracks range by tokenId.
    struct Range { 
        int24 lower; 
        int24 upper; 
    }
    
    function getRangeById(uint256 tokenId) public view returns (int24 lower, int24 upper) {
        lower = ranges[tokenId].lower;
        upper = ranges[tokenId].upper;
    }

    function supportsInterface(bytes4 sig) external pure returns (bool) {
        return (sig == 0x80ac58cd || sig == 0x5b5e139f); // @dev ERC-165.
    }
    
    function approve(address spender, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "!owner/operator");
        getApproved[tokenId] = spender;
        emit Approval(msg.sender, spender, tokenId); 
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function _mint(
        int24 lower, 
        int24 upper, 
        uint256 amount,
        address recipient
    ) internal {
        positions[lower][upper].totalSupply += amount;
        unchecked {
            positions[lower][upper].balanceOf[recipient] += amount;
        }
        if (positions[lower][upper].balanceOf[recipient] == 0) {
            totalSupply++;
            uint256 tokenId = totalSupply;
            ranges[tokenId].lower = lower;
            ranges[tokenId].upper = upper;
            emit Transfer(address(0), recipient, tokenId); // @dev Notices opening position by minting NFT.
        }
    }

    function _burn(
        uint256 tokenId,
        address from, 
        uint256 amount
    ) internal {
        int24 lower = ranges[tokenId].lower;
        int24 upper = ranges[tokenId].upper;
        positions[lower][upper].balanceOf[from] -= amount;
        unchecked {
            positions[lower][upper].totalSupply -= amount;
        }
        if (positions[lower][upper].balanceOf[from] == 0) {
            totalSupply--;
            emit Transfer(from, address(0), tokenId); // @dev Notices closing position by burning NFT.
        }
    }

    function transfer(address recipient, uint256 tokenId) external {
        require(msg.sender == ownerOf[tokenId], '!owner');
        balanceOf[msg.sender]--; 
        balanceOf[recipient]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = recipient;
        (int24 lower, int24 upper) = getRangeById(tokenId);
        positions[lower][upper].balanceOf[recipient] = positions[lower][upper].balanceOf[msg.sender]; // @dev Update recipient balance.
        positions[lower][upper].balanceOf[msg.sender] = 0; // @dev Nullify sender balance.
        emit Transfer(msg.sender, recipient, tokenId); 
    }
    
    function transferFrom(address, address recipient, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(msg.sender == owner || msg.sender == getApproved[tokenId] || isApprovedForAll[owner][msg.sender], '!owner/spender/operator');
        balanceOf[owner]--; 
        balanceOf[recipient]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = recipient;
        (int24 lower, int24 upper) = getRangeById(tokenId);
        positions[lower][upper].balanceOf[recipient] = positions[lower][upper].balanceOf[owner]; // @dev Update recipient balance.
        positions[lower][upper].balanceOf[owner] = 0; // @dev Nullify sender balance.
        emit Transfer(owner, recipient, tokenId); 
    }
}

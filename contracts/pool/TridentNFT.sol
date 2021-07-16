// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

contract TridentNFT {
    uint256 public totalSupply; // tracks total unique liquidity `triPts` 
    string constant public name = "TridentNFT";
    string constant public symbol = "tNFT";
    string constant public baseURI = "PLACEHOLDER"; // WIP - make chain-based, auto-generative image re: positions?
    
    mapping(address => uint256) public balanceOf; // tracks `triPts` held by an account
    mapping(uint256 => address) public getApproved;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => string) public tokenURI;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    
    event Approval(address indexed approver, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed approver, address indexed operator, bool approved);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    mapping(int24 => mapping(int24 => TickPool) public tickPools;
    struct TickPool { // virtual pool for concentrated liquidity in tick range
        uint112 liquidity; // last range liquidity 
        uint256 totalSupply; // total range mint for pool range providers
        mapping(address => uint256) balanceOf; // account provider range mint balance
    }
    
    mapping(uint256 => Range) public ranges; // tracks range by tokenId
    struct Range { 
        int24 lower; 
        int24 upper; 
    }
    
    function getRangeById(uint256 tokenId) public view returns (int24 loPt, int24 hiPt) {
        loPt = ranges[tokenId].loPt;
        hiPt = ranges[tokenId].hiPt;
    }

    function supportsInterface(bytes4 sig) external pure returns (bool) {
        return (sig == 0x80ac58cd || sig == 0x5b5e139f); // ERC-165
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
        address to, 
        uint256 amount
    ) internal {
        tickPools[lower][upper].totalSupply += amount;
        tickPools[lower][upper].balanceOf[to] += amount;
        if (tickPools[lower][upper].balanceOf[to] == 0) {
            totalSupply++;
            uint256 tokenId = totalSupply;
            ranges[tokenId].lower = loPt;
            ranges[tokenId].upper = hiPt;
            emit Transfer(address(0), to, tokenId); // notices opening position
        }
    }

    function _burn(
        uint256 tokenId,
        address from, 
        uint256 amount
    ) internal {
        int24 lower = ranges[tokenId].lower;
        int24 upper = ranges[tokenId].upper;
        tickPools[lower][upper].balanceOf[from] -= amount;
        unchecked {
            tickPools[lower][upper].totalSupply -= amount;
        }
        if (tickPools[lower][upper].balanceOf[from] == 0) {
            totalSupply--;
            emit Transfer(from, address(0), tokenId); // notices closing position
        }
    }
    
    function _swapBurn(
        int24 lower, 
        int24 upper, 
        address from, 
        uint256 amount
    ) internal {
        tickPools[lower][upper].balanceOf[from] -= amount;
        unchecked {
            tickPools[lower][upper].totalSupply -= amount;
        }
    }

    function transfer(address to, uint256 tokenId) external {
        require(msg.sender == ownerOf[tokenId], '!owner');
        balanceOf[msg.sender]--; 
        balanceOf[to]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = to;
        (int24 lower, int24 upper) = getRangeById(tokenId);
        tickPools[lower][upper].balanceOf[to] = tickPools[lower][upper].balanceOf[msg.sender]; // update recipient balance
        tickPools[lower][upper].balanceOf[msg.sender] = 0; // nullify sender balance
        emit Transfer(msg.sender, to, tokenId); 
    }
    
    function transferFrom(address, address to, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(msg.sender == owner || msg.sender == getApproved[tokenId] || isApprovedForAll[owner][msg.sender], '!owner/spender/operator');
        balanceOf[owner]--; 
        balanceOf[to]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = to;
        (int24 loPt, int24 hiPt) = getRangeById(tokenId);
        tickPools[lower][upper].balanceOf[to] = tickPools[lower][upper].balanceOf[owner]; // update recipient balance
        tickPools[lower][upper].balanceOf[owner] = 0; // nullify sender balance
        emit Transfer(owner, to, tokenId); 
    }
}

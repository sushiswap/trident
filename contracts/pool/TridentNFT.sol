// SPDX-License-Identifier: MIT

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
    
    mapping(uint256 => Range) public ranges; // tracks `Tripoint` range by tokenId
    struct Range { 
        uint256 loPt; 
        uint256 hiPt; 
    }
    
    mapping(uint256 => mapping(uint256 => Tripoint)) public triPts; // tracks liquidity updates in `Tripoint` range
    struct Tripoint { // virtual pool in liquidity `triPts` range (lo| |hi)
        uint112 reserve0; // last token0 balance
        uint112 reserve1; // last token1 balance
        uint256 totalSupply; // total for pool providers
        mapping(address => uint256) balanceOf; // account provider balance
    }

    function supportsInterface(bytes4 sig) external pure returns (bool) {
        return (sig == 0x80ac58cd || sig == 0x5b5e139f); // ERC-165
    }
    
    function getRangeById(uint256 tokenId) public view returns (uint256 loPt, uint256 hiPt) {
        loPt = ranges[tokenId].loPt;
        hiPt = ranges[tokenId].hiPt;
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
        uint256 loPt, 
        uint256 hiPt, 
        address to, 
        uint256 value
    ) internal {
        triPts[loPt][hiPt].totalSupply += value;
        triPts[loPt][hiPt].balanceOf[to] += value;
        if (triPts[loPt][hiPt].balanceOf[to] == 0) {
            totalSupply++;
            uint256 tokenId = totalSupply;
            ranges[tokenId].loPt = loPt;
            ranges[tokenId].hiPt = hiPt;
            emit Transfer(address(0), to, tokenId); // notices opening position
        }
    }

    function _burn(
        uint256 tokenId,
        address from, 
        uint256 value
    ) internal {
        uint256 loPt = ranges[tokenId].loPt;
        uint256 hiPt = ranges[tokenId].hiPt;
        triPts[loPt][hiPt].balanceOf[from] -= value;
        unchecked {
            triPts[loPt][hiPt].totalSupply -= value;
        }
        if (triPts[loPt][hiPt].balanceOf[from] == 0) {
            totalSupply--;
            emit Transfer(from, address(0), tokenId); // notices closing position
        }
    }
    
    function _swapBurn(
        uint256 hiPt, 
        uint256 loPt, 
        address from, 
        uint256 value
    ) internal {
        triPts[loPt][hiPt].balanceOf[from] -= value;
        unchecked {
            triPts[loPt][hiPt].totalSupply -= value;
        }
    }

    function transfer(address to, uint256 tokenId) external {
        require(msg.sender == ownerOf[tokenId], '!owner');
        balanceOf[msg.sender]--; 
        balanceOf[to]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = to;
        (uint256 loPt, uint256 hiPt) = getRangeById(tokenId);
        triPts[loPt][hiPt].balanceOf[to] = triPts[loPt][hiPt].balanceOf[msg.sender];
        triPts[loPt][hiPt].balanceOf[msg.sender] = 0;
        emit Transfer(msg.sender, to, tokenId); 
    }
    
    function transferFrom(address, address to, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(msg.sender == owner || msg.sender == getApproved[tokenId] || isApprovedForAll[owner][msg.sender], '!owner/spender/operator');
        balanceOf[owner]--; 
        balanceOf[to]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = to;
        (uint256 loPt, uint256 hiPt) = getRangeById(tokenId);
        triPts[loPt][hiPt].balanceOf[to] = triPts[loPt][hiPt].balanceOf[owner];
        triPts[loPt][hiPt].balanceOf[owner] = 0;
        emit Transfer(owner, to, tokenId); 
    }
}

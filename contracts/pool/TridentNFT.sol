pragma solidity ^0.8.2;

contract TridentNFT { // to-do- review 1155
    uint256 public totalSupply;
    string constant public name = "TridentNFT";
    string constant public symbol = "tNFT";
    string constant public baseURI = "PLACEHOLDER"; // WIP - make chain-based, auto-generative re: positions
    
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => Position) public positions;
    mapping(uint256 => address) public getApproved;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => string) public tokenURI;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    
    event Approval(address indexed approver, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed approver, address indexed operator, bool approved);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    struct Position {
        uint256 lower;
        uint256 upper;
        uint256 amount0;
        uint256 amount1;
        uint256 share;
        uint256 collected0;
        uint256 collected1;
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
        address to, 
        uint256 lower, 
        uint256 upper, 
        uint256 amount0, 
        uint256 amount1,
        uint256 share
    ) internal returns (uint256 tokenId) { 
        totalSupply++;
        tokenId = totalSupply;
        balanceOf[to]++;
        positions[tokenId] = Position(lower, upper, amount0, amount1, share, 0, 0);
        ownerOf[tokenId] = to;
        tokenURI[tokenId] = baseURI;
        emit Transfer(address(0), to, tokenId); 
    }
    // to-do - separate out total burn, which consumes all locked value, and piecemeal 'collect'
    function _burn(uint256 tokenId) internal {
        require(msg.sender == ownerOf[tokenId], '!owner');
        totalSupply--;
        balanceOf[msg.sender]--;
        ownerOf[tokenId] = address(0);
        tokenURI[tokenId] = "";
        emit Transfer(msg.sender, address(0), tokenId); 
    }

    function transfer(address to, uint256 tokenId) external {
        require(msg.sender == ownerOf[tokenId], '!owner');
        balanceOf[msg.sender]--; 
        balanceOf[to]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = to;
        emit Transfer(msg.sender, to, tokenId); 
    }
    
    function transferFrom(address, address to, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(msg.sender == owner || msg.sender == getApproved[tokenId] || isApprovedForAll[owner][msg.sender], '!owner/spender/operator');
        balanceOf[owner]--; 
        balanceOf[to]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = to;
        emit Transfer(owner, to, tokenId); 
    }
}

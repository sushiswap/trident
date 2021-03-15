// SPDX-License-Identifier: MIT

pragma solidity >=0.8.2;

import "./mixins/ERC721.sol";

/**
 * @dev Originally DeriswapV1LoanContracts
 * @author Andre Cronje, LevX
 */
contract MirinLoanContracts is ERC721 {
    address public immutable RESERVE;

    constructor() ERC721("MirinLoans", "MIRINL") {
        RESERVE = msg.sender;
    }

    function mint(address owner, uint256 id) external {
        require(msg.sender == RESERVE);
        _mint(owner, id);
    }

    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool) {
        return _isApprovedOrOwner(spender, tokenId);
    }
}

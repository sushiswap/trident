pragma solidity ^0.8.2;

import "../../contracts/pool/HybridPool.sol";

contract HybridPoolHarness is HybridPool {
    constructor(bytes memory _deployData, address _masterDeployer)
            HybridPool(_deployData, _masterDeployer) { }

    function tokenBalanceOf(IERC20 token, address user)
            public view returns (uint256 balance) {
        return token.balanceOf(user);
    }
}
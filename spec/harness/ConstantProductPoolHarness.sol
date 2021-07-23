pragma solidity ^0.8.2;

import "../../contracts/pool/ConstantProductPool.sol";

contract ConstantProductPoolHarness is ConstantProductPool {
    constructor(bytes memory _deployData, address _masterDeployer)
            ConstantProductPool(_deployData, _masterDeployer) { }

    function burnGetter(address to, bool unwrapBento) public lock
            returns (uint256 liquidity0_, uint256 liquidity1_) {
        liquidityAmount[] memory withdrawnAmounts = burn(to, unwrapBento);

        // Assuming in BentoBox shares (Ask Nurit)
        return (withdrawnAmounts[0].amount, withdrawnAmounts[1].amount);
    }

    function tokenBalanceOf(IERC20 token, address user)
            public view returns (uint256 balance) {
        return token.balanceOf(user);
    }
}
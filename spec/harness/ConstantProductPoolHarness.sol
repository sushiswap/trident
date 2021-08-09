pragma solidity ^0.8.2;

import "../../contracts/pool/ConstantProductPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ConstantProductPoolHarness is ConstantProductPool {
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) public amountOutHarness;

    constructor(bytes memory _deployData, address _masterDeployer)
            ConstantProductPool(_deployData, _masterDeployer) { }

    // a getter for the results from burn
    function burnGetter(address to, bool unwrapBento) public
            returns (uint256 liquidity0_, uint256 liquidity1_) {
        liquidityAmount[] memory withdrawnAmounts = super.burn(to, unwrapBento);

        // Assuming in BentoBox shares (Ask Nurit)
        return (withdrawnAmounts[0].amount, withdrawnAmounts[1].amount);
    }

    // override burn since we have the burnGetter - to save time
    function burn(address to, bool unwrapBento)
        public override returns (liquidityAmount[] memory withdrawnAmounts) { }

    function tokenBalanceOf(IERC20 token, address user)
            public view returns (uint256 balance) {
        return token.balanceOf(user);
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view override returns (uint256) {
        if (amountIn == 0 || reserveOut == 0) {
            return 0;
        }

        return amountOutHarness[amountIn][reserveIn][reserveOut];
    }
}
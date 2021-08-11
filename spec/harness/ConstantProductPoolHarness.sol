pragma solidity ^0.8.2;

import "../../contracts/pool/ConstantProductPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ConstantProductPoolHarness is ConstantProductPool {
    // state variables ///////////
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) public amountOutHarness;

    // constructor ///////////////
    constructor(bytes memory _deployData, address _masterDeployer)
            ConstantProductPool(_deployData, _masterDeployer) { }

    // getters ///////////////////
    function burnGetter(address to, bool unwrapBento) public
            returns (uint256 liquidity0_, uint256 liquidity1_) {
        liquidityAmount[] memory withdrawnAmounts = super.burn(to, unwrapBento);

        // Assuming in BentoBox shares (Ask Nurit)
        return (withdrawnAmounts[0].amount, withdrawnAmounts[1].amount);
    }

    function tokenBalanceOf(IERC20 token, address user)
            public view returns (uint256 balance) {
        return token.balanceOf(user);
    }

    // simplifications ///////////
    // TODO: If it works, maybe override swapWithContext, (Check with Nurit)
    function swapWithContextWrapper(
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        bool unwrapBento,
        uint256 amountIn
    ) public returns (uint256 amountOut) { 
        require(recipient != address(this), "recepient is current contract");
        // require(recipient != token0, "recepient is token0");
        // require(recipient != token1, "recepient is token1");

        // require(tokenIn == token0, "wrong token");
        // require(tokenOut == token1, "wrong token");

        return super.swapWithContext(tokenIn, tokenOut, context,
                                     recipient, unwrapBento, amountIn);
    }

    // override burn since we have the burnGetter - to save time
    function burn(address to, bool unwrapBento)
        public override returns (liquidityAmount[] memory withdrawnAmounts) { }

    // function _getAmountOut(
    //     uint256 amountIn,
    //     uint256 reserveIn,
    //     uint256 reserveOut
    // ) internal view override returns (uint256) {
    //     if (amountIn == 0 || reserveOut == 0) {
    //         return 0;
    //     }

    //     return amountOutHarness[amountIn][reserveIn][reserveOut];
    // }
}
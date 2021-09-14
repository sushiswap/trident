// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../pool/TridentERC20.sol";

/// @notice Intermediary token user's will receive after migration.
/// Can be redeemed for the LP token of the new pool.
contract IntermediaryToken is TridentERC20 {
    TridentERC20 public immutable lpToken;
    uint256 public desiredLiquidity;

    constructor(
        address _lpToken,
        address _recipient,
        uint256 _amount
    ) {
        lpToken = TridentERC20(_lpToken);
        _mint(_recipient, _amount);
    }

    function deposit(uint256 amount) public {
        uint256 availableLpTokens = lpToken.balanceOf(address(this));
        uint256 toMint = (totalSupply * amount) / availableLpTokens;
        _mint(msg.sender, toMint);
        lpToken.transferFrom(msg.sender, address(this), amount);
    }

    function redeem() public {
        uint256 availableLpTokens = lpToken.balanceOf(address(this));
        uint256 amountToBurn = balanceOf[msg.sender];
        uint256 claimAmount = (availableLpTokens * amountToBurn) / totalSupply;
        _burn(msg.sender, amountToBurn);
        lpToken.transfer(msg.sender, claimAmount);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../pool/TridentERC20.sol";
import {IERC20} from "./Migrator.sol";

/// @notice Intermediary token users who are staked in MasterChef will receive after migration.
/// Can be redeemed for the LP token of the new pool.
contract IntermediaryToken is TridentERC20 {
    /// @dev Liquidity token of the Trident constant product pool.
    IERC20 public immutable lpToken;

    constructor(
        address _lpToken,
        address _recipient,
        uint256 _amount
    ) {
        lpToken = IERC20(_lpToken);
        _mint(_recipient, _amount);
    }

    /// @dev Since we might be rewarding the intermediary token for some time we allow users to mint it.
    function deposit(uint256 amount) public {
        uint256 availableLpTokens = lpToken.balanceOf(address(this));
        uint256 toMint = (totalSupply * amount) / availableLpTokens;
        _mint(msg.sender, toMint);
        lpToken.transferFrom(msg.sender, address(this), amount);
    }

    function redeem(uint256 amount) public {
        uint256 availableLpTokens = lpToken.balanceOf(address(this));
        uint256 claimAmount = (availableLpTokens * amount) / totalSupply;
        _burn(msg.sender, amount);
        lpToken.transfer(msg.sender, claimAmount);
    }
}

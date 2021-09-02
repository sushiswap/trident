// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../workInProgress/IMigrator.sol";

/// @notice Trident pool migrator contract for legacy SushiSwap.
contract Migrator {
    address public immutable bento;
    address public immutable masterChef;
    address public immutable masterDeployer;
    address public immutable pairPoolDeployer;
    address public immutable wETH;
    uint256 public desiredLiquidity;

    constructor(
        address _bento,
        address _masterChef,
        address _masterDeployer,
        address _pairPoolDeployer,
        address _wETH
    ) {
        bento = _bento;
        masterChef = _masterChef;
        masterDeployer = _masterDeployer;
        pairPoolDeployer = _pairPoolDeployer;
        wETH = _wETH;
        desiredLiquidity = type(uint256).max;
    }
    
    function migrate(address origin, address destination, address factory, bytes calldata deployData) external returns (address pair) {
        require(msg.sender == masterChef, "NOT_CHEF");
        // @dev Get the `origin` pair tokens.
        (, bytes memory _token0) = origin.staticcall(abi.encodeWithSelector(IMigrator.token0.selector)); 
        (, bytes memory _token1) = origin.staticcall(abi.encodeWithSelector(IMigrator.token1.selector)); 
        address token0 = abi.decode(_token0, (address));
        address token1 = abi.decode(_token1, (address));
        {
            // @dev If `destination` is uninitialized, deploy.
            if (destination == address(0)) {
                (bool deploySuccess, bytes memory _newPair) = masterDeployer.call(abi.encodeWithSelector(IMigrator.deployPool.selector, factory, deployData));
                require(deploySuccess, "DEPLOY_FAILED");
                pair = abi.decode(_newPair, (address));
            } else {
                // @dev Check `destination` LP has not already initialized.
                (, bytes memory _totalSupply) = origin.staticcall(abi.encodeWithSelector(IMigrator.totalSupply.selector));
                uint256 totalSupply = abi.decode(_totalSupply, (uint256));
                require(totalSupply == 0, "PAIR_ALREADY_INITIALIZED");
            }
        }
        // @dev Get `origin` LP balance from `MasterChef`.
        uint256 lp = _balanceOf(origin, msg.sender);
        if (lp == 0) return pair;
        
        // @dev Forward `origin` LP balance from `MasterChef` to `origin` for burn.
        (bool transferFromSuccess, bytes memory transferFromData) = origin.call(abi.encodeWithSelector(IMigrator.transferFrom.selector, msg.sender, origin, lp));
        require(transferFromSuccess && (transferFromData.length == 0 || abi.decode(transferFromData, (bool))), "TRANSFER_FROM_FAILED");
        // @dev Complete LP migration with burn from `origin` and mint into `destination` pair.
        desiredLiquidity = lp;
        
        (bool burnSuccess, bytes memory burnData) = origin.call(abi.encodeWithSelector(IMigrator.burn.selector, bento)); 
        require(burnSuccess, "BURN_FAILED");
        (uint256 amount0, uint256 amount1) = abi.decode(burnData, (uint256, uint256));
        
        _depositToBentoBox(token0, pair, amount0);
        _depositToBentoBox(token1, pair, amount1);
        
        (bool mintSuccess, ) = pair.call(abi.encodeWithSelector(IMigrator.mint.selector, abi.encode(msg.sender)));
        require(mintSuccess, "MINT_FAILED");
        
        desiredLiquidity = type(uint256).max;
        return pair;
    }
    
    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool balanceSuccess, bytes memory balanceData) = token.staticcall(abi.encodeWithSelector(IMigrator.balanceOf.selector, account));
        require(balanceSuccess && balanceData.length >= 32, "BALANCE_OF_FAILED");
        balance = abi.decode(balanceData, (uint256));
    }

    function _depositToBentoBox(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (token == wETH && address(this).balance != 0) {
            (, bytes memory _underlyingAmount) = bento.call(abi.encodeWithSelector(IMigrator.toAmount.selector, wETH, amount, true));
            uint256 underlyingAmount = abi.decode(_underlyingAmount, (uint256));
            if (address(this).balance > underlyingAmount) {
                // @dev Deposit ETH into `recipient` `bento` account.
                (bool ethDepositSuccess, ) = bento.call{value: underlyingAmount}(abi.encodeWithSelector(IMigrator.deposit.selector, token, msg.sender, recipient, amount));
                require(ethDepositSuccess, "ETH_DEPOSIT_FAILED");
                return;
            }
        }
        // @dev Deposit ERC-20 token into `recipient` `bento` account.
        (bool depositSuccess, ) = bento.call(abi.encodeWithSelector(IMigrator.deposit.selector, token, msg.sender, recipient, amount));
        require(depositSuccess, "DEPOSIT_FAILED");
    }
}

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
    
    /// @notice Migration method to replace legacy SushiSwap with Trident liquidity tokens.
    /// @param origin Legacy SushiSwap pair pool.
    /// @param destination Target Trident pair pool.
    /// @param factory Factory for Trident pair pool - TO-DO hardcode since constant product is assumed?.
    /// @param deployData The payload for Trident pair pool configuration - leave null if already initialized.
    /// @return pool Confirms Trident pair pool `destination`.
    function migrate(address origin, address destination, address factory, bytes calldata deployData) external returns (address pool) {
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
                pool = abi.decode(_newPair, (address));
            } else {
                // @dev Check `destination` LP has not already initialized.
                (, bytes memory _totalSupply) = origin.staticcall(abi.encodeWithSelector(IMigrator.totalSupply.selector));
                uint256 totalSupply = abi.decode(_totalSupply, (uint256));
                require(totalSupply == 0, "PAIR_ALREADY_INITIALIZED");
            }
        }
        // @dev Get `origin` LP balance from `MasterChef`.
        uint256 lp = _balanceOf(origin);
        if (lp == 0) return pool;
        
        // @dev Forward `origin` LP balance from `MasterChef` to `origin` for burn.
        (bool transferFromSuccess, bytes memory transferFromData) = origin.call(abi.encodeWithSelector(IMigrator.transferFrom.selector, msg.sender, origin, lp));
        require(transferFromSuccess && (transferFromData.length == 0 || abi.decode(transferFromData, (bool))), "TRANSFER_FROM_FAILED");
        // @dev Complete LP migration with burn from `origin` and mint into `destination` pair.
        desiredLiquidity = lp;
        
        (bool burnSuccess, bytes memory burnData) = origin.call(abi.encodeWithSelector(IMigrator.burn.selector, bento)); 
        require(burnSuccess, "BURN_FAILED");
        (uint256 amount0, uint256 amount1) = abi.decode(burnData, (uint256, uint256));
        
        _depositToBentoBox(token0, pool, amount0);
        _depositToBentoBox(token1, pool, amount1);
        
        (bool mintSuccess, ) = pool.call(abi.encodeWithSelector(IMigrator.mint.selector, abi.encode(msg.sender)));
        require(mintSuccess, "MINT_FAILED");
        
        desiredLiquidity = type(uint256).max;
        return pool;
    }
    
    function _balanceOf(address token) internal view returns (uint256 balance) {
        (bool balanceSuccess, bytes memory balanceData) = token.staticcall(abi.encodeWithSelector(IMigrator.balanceOf.selector, msg.sender));
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
    
    /// @notice Provides batch function calls for this contract and returns the data from all of them if they all succeed.
    /// Adapted from https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/base/Multicall.sol, License-Identifier: GPL-2.0-or-later.
    /// @dev The `msg.value` should not be trusted for any method callable from this function.
    /// @param data ABI-encoded params for each of the calls to make to this contract.
    /// @return results The results from each of the calls passed in via `data`.
    function batch(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                // @dev Next 5 lines from https://ethereum.stackexchange.com/a/83577.
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }
            results[i] = result;
        }
    }
    
    /// @notice Provides EIP-2612 signed approval for this contract to spend user tokens.
    /// @param token Address of ERC-20 token.
    /// @param amount Token amount to grant spending right over.
    /// @param deadline Termination for signed approval (UTC timestamp in seconds).
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    function permitThis(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        (bool success, ) = token.call(
            abi.encodeWithSelector(0xd505accf, msg.sender, address(this), amount, deadline, v, r, s)
        ); // @dev permit(address,address,uint256,uint256,uint8,bytes32,bytes32).
        require(success, "PERMIT_FAILED");
    }
}

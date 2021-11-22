// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IMasterDeployer.sol";
import "../TridentRouter.sol";
import "./TridentPermit.sol";

/// @notice Trident router helper contract.
contract RouterHelper is TridentPermit {
    /// @notice BentoBox token vault.
    IBentoBoxMinimal public immutable bento;
    /// @notice Trident AMM master deployer contract.
    IMasterDeployer public immutable masterDeployer;
    /// @notice ERC-20 token for wrapped ETH (v9).
    address internal immutable wETH;
    /// @notice The user should use 0x0 if they want to deposit ETH
    address constant USE_ETHEREUM = address(0);

    constructor(
        IBentoBoxMinimal _bento,
        IMasterDeployer _masterDeployer,
        address _wETH
    ) {
        bento = _bento;
        masterDeployer = _masterDeployer;
        wETH = _wETH;
        _bento.registerProtocol();
    }

    /// @notice Provides batch function calls for this contract and returns the data from all of them if they all succeed.
    /// Adapted from https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/base/Multicall.sol, License-Identifier: GPL-2.0-or-later.
    /// @dev The `msg.value` should not be trusted for any method callable from this function.
    /// @dev Uses a modified version of the batch function - preventing multiple calls of the single input swap functions
    /// @param data ABI-encoded params for each of the calls to make to this contract.
    /// @return results The results from each of the calls passed in via `data`.
    function batch(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        // We only allow one exactInputSingle call to be made in a single batch call.
        // This is not really needed but we want to save users from signing malicious payloads.
        // We also don't want nested batch calls.
        bool swapCalled;
        for (uint256 i = 0; i < data.length; i++) {
            bytes4 selector = getSelector(data[i]);
            if (selector == TridentRouter.exactInputSingle.selector || selector == TridentRouter.exactInputSingleWithNativeToken.selector) {
                require(!swapCalled, "Swap called twice");
                swapCalled = true;
            } else {
                require(selector != this.batch.selector, "Nested Batch");
            }

            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577.
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }
            results[i] = result;
        }
    }

    function deployPool(address factory, bytes calldata deployData) external payable returns (address) {
        return masterDeployer.deployPool(factory, deployData);
    }

    /// @notice Helper function to allow batching of BentoBox master contract approvals so the first trade can happen in one transaction.
    function approveMasterContract(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        bento.setMasterContractApproval(msg.sender, address(this), true, v, r, s);
    }

    /// @notice Provides gas-optimized balance check on this contract to avoid redundant extcodesize check in addition to returndatasize check.
    /// @param token Address of ERC-20 token.
    /// @return balance Token amount held by this contract.
    function balanceOfThis(address token) internal view returns (uint256 balance) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(0x70a08231, address(this))); // @dev balanceOf(address).
        require(success && data.length >= 32, "BALANCE_OF_FAILED");
        balance = abi.decode(data, (uint256));
    }

    /// @notice Provides 'safe' ERC-20 {transfer} for tokens that don't consistently return true/false.
    /// @param token Address of ERC-20 token.
    /// @param recipient Account to send tokens to.
    /// @param amount Token amount to send.
    function safeTransfer(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, recipient, amount)); // @dev transfer(address,uint256).
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    /// @notice Provides 'safe' ERC-20 {transferFrom} for tokens that don't consistently return true/false.
    /// @param token Address of ERC-20 token.
    /// @param sender Account to send tokens from.
    /// @param recipient Account to send tokens to.
    /// @param amount Token amount to send.
    function safeTransferFrom(
        address token,
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, sender, recipient, amount)); // @dev transferFrom(address,address,uint256).
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    /// @notice Provides low-level `wETH` {withdraw}.
    /// @param amount Token amount to unwrap into ETH.
    function withdrawFromWETH(uint256 amount) internal {
        (bool success, ) = wETH.call(abi.encodeWithSelector(0x2e1a7d4d, amount)); // @dev withdraw(uint256).
        require(success, "WITHDRAW_FROM_WETH_FAILED");
    }

    /// @notice Provides 'safe' ETH transfer.
    /// @param recipient Account to send ETH to.
    /// @param amount ETH amount to send.
    function safeTransferETH(address recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH_TRANSFER_FAILED");
    }

    /**
     * @notice function to extract the selector of a bytes calldata
     * @param _data the calldata bytes
     */
    function getSelector(bytes memory _data) internal pure returns (bytes4 sig) {
        assembly {
            sig := mload(add(_data, 32))
        }
    }
}

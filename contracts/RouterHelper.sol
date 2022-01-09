// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./interfaces/IBentoBoxMinimal.sol";
import "./interfaces/IMasterDeployer.sol";
import "./TridentPermit.sol";
import "./TridentBatchable.sol";

/// @notice Trident router helper contract.
contract RouterHelper is TridentPermit, TridentBatchable {
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

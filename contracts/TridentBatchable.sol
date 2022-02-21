// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0;

/// @notice Generic contract exposing the batch call functionality.
abstract contract TridentBatchable {
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
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}

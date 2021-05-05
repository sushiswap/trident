// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinERC20.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IMirinFactory.sol";

/**
 * @author LevX
 */
contract MirinGovernance is MirinERC20 {
    uint8 public constant MIN_SWAP_FEE = 1;
    uint8 public constant MAX_SWAP_FEE = 100;

    address public immutable factory;

    /**
     * @dev If empty, this is a public pool.
     */
    address public operator;

    /**
     * @dev Fee for swapping (out of 1000)
     */
    uint8 public swapFee;

    /**
     * @dev Swap fee receiver
     */
    address public swapFeeTo;

    /**
     * @dev A blacklisted account cannot mint and burn
     */
    mapping(address => bool) public blacklisted;

    event OperatorSet(address indexed previousOperator, address indexed newOperator);
    event SwapFeeUpdated(uint8 newFee);
    event SwapFeeToUpdated(address newFeeTo);
    event BlacklistAdded(address indexed account);
    event BlacklistRemoved(address indexed account);

    modifier onlyOperator() {
        require(operator == msg.sender, "MIRIN: UNAUTHORIZED");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "MIRIN: BLACKLISTED");
        _;
    }

    constructor(
        address _operator,
        uint8 _fee,
        address _feeTo
    ) {
        factory = msg.sender;
        operator = _operator;

        if (_operator == address(0)) {
            _updateSwapFee(3);
        } else {
            _updateSwapFee(_fee);
            _updateSwapFeeTo(_feeTo);
        }
    }

    function setOperator(address newOperator) external onlyOperator {
        require(newOperator != address(0), "MIRIN: INVALID_OPERATOR");
        emit OperatorSet(operator, newOperator);
        operator = newOperator;
    }

    function _updateSwapFee(uint8 newFee) internal {
        require(newFee >= MIN_SWAP_FEE && newFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");

        swapFee = newFee;

        emit SwapFeeUpdated(newFee);
    }

    function _updateSwapFeeTo(address newFeeTo) internal {
        swapFeeTo = newFeeTo;

        emit SwapFeeToUpdated(newFeeTo);
    }

    function disable(address to) external onlyOperator {
        IMirinFactory(factory).disablePool(to);
    }

    function addToBlacklist(address[] calldata accounts) external onlyOperator {
        for (uint256 i; i < accounts.length; i++) {
            blacklisted[accounts[i]] = true;
            emit BlacklistAdded(accounts[i]);
        }
    }

    function removeFromBlacklist(address[] calldata accounts) external onlyOperator {
        for (uint256 i; i < accounts.length; i++) {
            blacklisted[accounts[i]] = false;
            emit BlacklistRemoved(accounts[i]);
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../interfaces/IERC20.sol";

interface IMirinFactory {
    function feeTo() external view returns (address);

    function owner() external view returns (address);

    function isPool(address pool) external view returns (bool);

    function disablePool(address to) external;
}

/**
 * @author LevX
 */
contract MirinGovernance {
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
            updateSwapFee(3);
        } else {
            updateSwapFee(_fee);
            updateSwapFeeTo(_feeTo);
        }
    }

    function setOperator(address newOperator) external {
        require(operator == msg.sender, "MIRIN: UNAUTHORIZED");
        require(newOperator != address(0), "MIRIN: INVALID_OPERATOR");
        emit OperatorSet(operator, newOperator);
        operator = newOperator;
    }

    function updateSwapFee(uint8 newFee) public onlyOperator {
        require(newFee >= MIN_SWAP_FEE && newFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");

        swapFee = newFee;

        emit SwapFeeUpdated(newFee);
    }

    function updateSwapFeeTo(address newFeeTo) public onlyOperator {
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

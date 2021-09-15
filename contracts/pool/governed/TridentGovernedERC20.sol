// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Trident pool ERC-20 with EIP-2612 extension.
/// @author Adapted from RariCapital, https://github.com/Rari-Capital/solmate/blob/main/src/erc20/ERC20.sol,
/// License-Identifier: AGPL-3.0-only.
abstract contract TridentGovernedERC20 {
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Transfer(address indexed sender, address indexed recipient, uint256 amount);
    /// @notice An event that's emitted when an account changes its delegate.
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    /// @notice An event that's emitted when a delegate account's vote balance changes.
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    string public constant name = "Sushi LP Token";
    string public constant symbol = "SLP";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    /// @notice owner -> balance mapping.
    mapping(address => uint256) public balanceOf;
    /// @notice owner -> spender -> allowance mapping.
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice The EIP-712 typehash for this contract's {permit} struct.
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    /// @notice The EIP-712 typehash for this contract's domain.
    bytes32 public immutable DOMAIN_SEPARATOR;
    /// @notice owner -> nonce mapping used in {permit}.
    mapping(address => uint256) public nonces;
    
    /// @notice The ERC-712 typehash for the delegation struct used by the contract.
    bytes32 constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
    /// @notice A record of each account's delegate.
    mapping(address => address) public delegates;
    /// @notice A record of votes checkpoints for each account, by index.
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;
    /// @notice The number of checkpoints for each account.
    mapping(address => uint32) public numCheckpoints;
    
    /// @notice A checkpoint for marking number of votes from a given block.
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Approves `amount` from `msg.sender` to be spent by `spender`.
    /// @param spender Address of the party that can pull tokens from `msg.sender`'s account.
    /// @param amount The maximum collective `amount` that `spender` can pull.
    /// @return (bool) Returns 'true' if succeeded.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers `amount` tokens from `msg.sender` to `recipient`.
    /// @param recipient The address to move tokens to.
    /// @param amount The token `amount` to move.
    /// @return (bool) Returns 'true' if succeeded.
    function transfer(address recipient, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        // @dev This is safe from overflow - the sum of all user
        // balances can't exceed 'type(uint256).max'.
        unchecked {
            balanceOf[recipient] += amount;
        }
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Transfers `amount` tokens from `sender` to `recipient`. Caller needs approval from `from`.
    /// @param sender Address to pull tokens `from`.
    /// @param recipient The address to move tokens to.
    /// @param amount The token `amount` to move.
    /// @return (bool) Returns 'true' if succeeded.
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (allowance[sender][msg.sender] != type(uint256).max) {
            allowance[sender][msg.sender] -= amount;
        }
        balanceOf[sender] -= amount;
        // @dev This is safe from overflow - the sum of all user
        // balances can't exceed 'type(uint256).max'.
        unchecked {
            balanceOf[recipient] += amount;
        }
        emit Transfer(sender, recipient, amount);
        return true;
    }

    /// @notice Triggers an approval from `owner` to `spender`.
    /// @param owner The address to approve from.
    /// @param spender The address to be approved.
    /// @param amount The number of tokens that are approved (2^256-1 means infinite).
    /// @param deadline The time at which to expire the signature.
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonces[owner]++, deadline)))
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_PERMIT_SIGNATURE");
        allowance[recoveredAddress][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address recipient, uint256 amount) internal {
        totalSupply += amount;
        // @dev This is safe from overflow - the sum of all user
        // balances can't exceed 'type(uint256).max'.
        unchecked {
            balanceOf[recipient] += amount;
        }
        emit Transfer(address(0), recipient, amount);
    }

    function _burn(address sender, uint256 amount) internal {
        balanceOf[sender] -= amount;
        // @dev This is safe from underflow - users won't ever
        // have a balance larger than `totalSupply`.
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(sender, address(0), amount);
    }
    
    /*******************
    DELEGATION FUNCTIONS
    *******************/
    /// @notice Delegate votes from `msg.sender` to `delegatee`.
    /// @param delegatee The address to delegate votes to.
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /// @notice Delegates votes from signatory to `delegatee`.
    /// @param delegatee The address to delegate votes to.
    /// @param nonce The contract state required to match the signature.
    /// @param expiry The time at which to expire the signature.
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_SEPARATOR, keccak256(bytes(name)), block.chainid, address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), 'Meowshi::delegateBySig: invalid signature');
        unchecked {require(nonce == nonces[signatory]++, 'Meowshi::delegateBySig: invalid nonce');}
        require(block.timestamp <= expiry, 'Meowshi::delegateBySig: signature expired');
        return _delegate(signatory, delegatee);
    }
    
    function _delegate(address delegator, address delegatee) private {
        address currentDelegate = delegates[delegator]; 
        uint256 delegatorBalance = balanceOf[delegator];
        delegates[delegator] = delegatee;
        emit DelegateChanged(delegator, currentDelegate, delegatee);
        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) private {
        unchecked {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }
            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }}
    }
    
    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint256 oldVotes, uint256 newVotes) private {
        uint32 blockNumber = safe32(block.number);
        unchecked {
        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }}
        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }
    
    /// @notice Gets the current votes balance for `account`.
    /// @param account The address to get votes balance.
    /// @return The number of current votes for `account`.
    function getCurrentVotes(address account) external view returns (uint256) {
        unchecked {uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;}
    }

    /// @notice Determine the prior number of votes for an `account` as of a block number.
    /// @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
    /// @param account The address of the `account` to check.
    /// @param blockNumber The block number to get the vote balance at.
    /// @return The number of votes the `account` had as of the given block.
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, 'Meowshi::getPriorVotes: not yet determined');
        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {return 0;}
        unchecked {
        // @dev First check most recent balance.
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {return checkpoints[account][nCheckpoints - 1].votes;}
        // @dev Next check implicit zero balance.
        if (checkpoints[account][0].fromBlock > blockNumber) {return 0;}
        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {upper = center - 1;}}
        return checkpoints[account][lower].votes;}
    }
    
    function safe32(uint256 n) private pure returns (uint32) {
        require(n < 2**32, 'Meowshi::_writeCheckpoint: block number exceeds 32 bits'); return uint32(n);}
}

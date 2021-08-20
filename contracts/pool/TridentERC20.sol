// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Contract for Trident pool ERC20 with EIP-2612 extension.
/// @dev Adapted from RariCapital (https://github.com/Rari-Capital/solmate/blob/main/src/erc20/ERC20.sol).
contract TridentERC20 {
    /*///////////////////////////////////////////////////////////////
                                  EVENTS
    //////////////////////////////////////////////////////////////*/
    event Transfer(address indexed from, address indexed recipient, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/
    string public constant name = "Sushi LP Token";
    string public constant symbol = "SLP";
    uint8 public constant decimals = 18;

    /*///////////////////////////////////////////////////////////////
                             ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public totalSupply;
    /// @notice owner -> balance mapping.
    mapping(address => uint256) public balanceOf;
    /// @notice owner -> spender -> allowance mapping.
    mapping(address => mapping(address => uint256)) public allowance;

    /*///////////////////////////////////////////////////////////////
                         PERMIT/EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice The EIP-712 typehash for the permit struct used by this contract.
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    /// @notice The EIP-712 typehash for this contract's domain.
    bytes32 public immutable DOMAIN_SEPARATOR;
    /// @notice owner -> nonce mapping used in {permit}.
    mapping(address => uint256) public nonces;

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    /*///////////////////////////////////////////////////////////////
                              ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Approves `amount` from msg.sender to be spent by `spender`.
    /// @param spender Address of the party that can draw tokens from msg.sender's account.
    /// @param amount The maximum collective `amount` that `spender` can draw.
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
        // @dev This is safe because the sum of all user
        // balances can't exceed type(uint256).max
        unchecked {
            balanceOf[recipient] += amount;
        }
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Transfers `amount` tokens from `from` to `recipient`. Caller needs approval from `from`.
    /// @param from Address to draw tokens `from`.
    /// @param recipient The address to move tokens to.
    /// @param amount The token `amount` to move.
    /// @return (bool) Returns 'true' if succeeded.
    function transferFrom(
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        // @dev This is safe because the sum of all user
        // balances can't exceed type(uint256).max
        unchecked {
            balanceOf[recipient] += amount;
        }
        emit Transfer(from, recipient, amount);
        return true;
    }

    /*///////////////////////////////////////////////////////////////
                          PERMIT/EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Triggers an approval from owner to spends.
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
        require(deadline >= block.timestamp, "TridentERC20: PERMIT_DEADLINE_EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "TridentERC20: INVALID_PERMIT_SIGNATURE");
        allowance[recoveredAddress][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /*///////////////////////////////////////////////////////////////
                          INTERNAL UTILS
    //////////////////////////////////////////////////////////////*/
    function _mint(address recipient, uint256 amount) internal {
        totalSupply += amount;
        // @dev This is safe because the sum of all user
        // balances can't exceed type(uint256).max
        unchecked {
            balanceOf[recipient] += amount;
        }
        emit Transfer(address(0), recipient, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        // @dev This is safe because a user won't ever
        // have a balance larger than totalSupply
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}

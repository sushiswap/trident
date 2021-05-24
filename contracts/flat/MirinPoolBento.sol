// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IMirinPool is IUniswapV2Pair {
    event OperatorSet(address indexed previousOperator, address indexed newOperator);
    event SwapFeeUpdated(uint8 newFee);
    event SwapFeeToUpdated(address newFeeTo);
    event BlacklistAdded(address indexed account);
    event BlacklistRemoved(address indexed account);
    event OptionCreated(
        uint256 id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 strike,
        uint256 created,
        uint256 expire
    );
    event OptionExercised(
        uint256 id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 strike,
        uint256 excercised,
        uint256 expire
    );

    function initialize() external;

    function MIN_SWAP_FEE() external view returns (uint8);

    function MAX_SWAP_FEE() external view returns (uint8);

    function operator() external view returns (address);

    function swapFee() external view returns (uint8);

    function swapFeeTo() external view returns (address);

    function blacklisted(address account) external view returns (bool);

    function setOperator(address newOperator) external;

    function updateSwapFee(uint8 newFee) external;

    function updateSwapFeeTo(address newFeeTo) external;

    function disable(address to) external;

    function addToBlacklist(address[] calldata accounts) external;

    function removeFromBlacklist(address[] calldata accounts) external;

    function curve() external view returns (address);

    function curveData() external view returns (bytes32);

    function pricePoints(uint256)
        external
        view
        returns (
            uint256 timestamp,
            uint256 price0Cumulative,
            uint256 price1Cumulative
        );

    function pricePointsLength() external view returns (uint256);

    function price(address token) external view returns (uint256);

    function realizedVariance(
        address tokenIn,
        uint256 p,
        uint256 window
    ) external view returns (uint256);

    function realizedVolatility(
        address tokenIn,
        uint256 p,
        uint256 window
    ) external view returns (uint256);

    function quotePrice(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut);

    function sample(
        address tokenIn,
        uint256 amountIn,
        uint256 p,
        uint256 window
    ) external view returns (uint256[] memory);

    function loanContracts() external view returns (address);

    function optionContracts() external view returns (address);

    function quoteOption(address tokenIn, uint256 t) external view returns (uint256 call, uint256 put);

    function quoteOptionPrice(
        address tokenIn,
        uint256 t,
        uint256 sp,
        uint256 st
    ) external view returns (uint256 call, uint256 put);

    function options(uint256)
        external
        view
        returns (
            address asset,
            uint256 amount,
            uint256 strike,
            uint256 expire,
            uint256 optionType
        );

    function optionsLength() external view returns (uint256);

    function feeDetail(
        address token,
        uint256 st,
        uint256 t,
        uint256 optionType
    )
        external
        view
        returns (
            uint256 _call,
            uint256 _put,
            uint256 _fee
        );

    function fee(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 optionType
    ) external view returns (uint256);

    function callATM(
        address token,
        uint256 amount,
        uint256 t,
        uint256 maxFee
    ) external;

    function putATM(
        address token,
        uint256 amount,
        uint256 t,
        uint256 maxFee
    ) external;

    function createCall(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 maxFee
    ) external;

    function createPut(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 maxFee
    ) external;

    function utilization(
        address token,
        uint256 optionType,
        uint256 amount
    ) external view returns (uint256);

    function createOption(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 optionType,
        uint256 maxFee
    ) external;

    function exerciseOptionProfitOnly(uint256 id) external;

    function exerciseOption(uint256 id) external;

    function updateCurveData(bytes32 data) external;

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external;

    function burn(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external;
}

interface IMirinFactory {
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        bool isPublic,
        uint256 length,
        address indexed pool,
        address operator
    );
    event PoolDisabled(address indexed pool);

    function SUSHI_DEPOSIT() external view returns (uint256);

    function SUSHI() external view returns (address);

    function feeTo() external view returns (address);

    function owner() external view returns (address);

    function isCurveWhitelisted(address curve) external view returns (bool);

    function getPublicPool(
        address token0,
        address token1,
        uint256 index
    ) external view returns (address);

    function getFranchisedPool(
        address token0,
        address token1,
        uint256 index
    ) external view returns (address);

    function isPool(address pool) external view returns (bool);

    function allPools(uint256 index) external view returns (address);

    function publicPoolsLength(address token0, address token1) external view returns (uint256);

    function franchisedPoolsLength(address token0, address token1) external view returns (uint256);

    function allPoolsLength() external view returns (uint256);

    function whitelistCurve(address curve) external;

    function createPool(
        address tokenA,
        address tokenB,
        address curve,
        bytes32 curveData,
        address operator,
        uint8 swapFee,
        address swapFeeTo
    ) external returns (address pool);

    function disablePool(address to) external;

    function setFeeTo(address _feeTo) external;

    function setOwner(address _owner) external;
}

/**
 * @dev Collection of functions related to the address type
 * @author Andre Cronje
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 weiValue,
        string memory errorMessage
    ) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{value: weiValue}(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint256);

    function symbol() external view returns (string memory);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

/**
 * @dev Originally DeriswapV1ERC20
 * @author Andre Cronje, LevX
 */
contract MirinERC20 {
    using SafeERC20 for IERC20;

    string public constant name = "Mirin";
    string public constant symbol = "MIRIN";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public immutable DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
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

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply + value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] = balanceOf[from] - value;
        totalSupply = totalSupply - value;
        emit Transfer(from, address(0), value);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        balanceOf[from] = balanceOf[from] - value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(from, to, value);
    }

    function _transferFrom(
        address from,
        address to,
        uint256 value
    ) internal {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] = allowance[from][msg.sender] - value;
        }
        _transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        _transferFrom(from, to, value);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
                )
            );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "MIRIN: INVALID_SIGNATURE");
        _approve(owner, spender, value);
    }
}

interface IMirinCurve {
    function canUpdateData(bytes32 oldData, bytes32 newData) external pure returns (bool);

    function isValidData(bytes32 data) external view returns (bool);

    function computeLiquidity(
        uint256 reserve0,
        uint256 reserve1,
        bytes32 data
    ) external view returns (uint256);

    function computePrice(
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 tokenIn
    ) external view returns (uint224);

    function computeAmountOut(
        uint256 amountIn,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view returns (uint256);

    function computeAmountIn(
        uint256 amountOut,
        uint112 reserve0,
        uint112 reserve1,
        bytes32 data,
        uint8 swapFee,
        uint8 tokenIn
    ) external view returns (uint256);
}

interface IBentoBoxV1 {
    function balanceOf(IERC20, address) external view returns (uint256);
    
    function deposit( 
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);

    function withdraw(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);

    function transfer(
        IERC20 token,
        address from,
        address to,
        uint256 share
    ) external;

    function transferMultiple(
        IERC20 token,
        address from,
        address[] calldata tos,
        uint256[] calldata shares
    ) external;
}

/// @notice Interface for low-level `swap()` call.
interface IMirinCallee {
    function mirinCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract MirinPool is MirinERC20 {
    /**
     * @dev Immutable variables for `masterContract` and all pool clones
     */
    IBentoBoxV1 private immutable bentoBox;
    MirinPool private immutable masterContract;

    /**
     * @notice `masterContract` variables
     */
    address public masterFeeTo;
    address public owner;

    mapping(address => bool) public isCurveWhitelisted;
    mapping(address => mapping(address => address)) public getPool;
    mapping(address => bool) public isPool;
    address[] public allPools;

    event PoolCreated(
        address indexed token0,
        address indexed token1,
        address indexed pool,
        uint256 length
    );
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    uint8 public constant MIN_SWAP_FEE = 1;
    uint8 public constant MAX_SWAP_FEE = 100;
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;

    /**
     * @dev Fee for swapping (out of 1000).
     */
    uint8 public swapFee;
    /**
     * @dev Swap fee receiver.
     */
    address public swapFeeTo;

    address public token0;
    address public token1;

    address public curve;
    bytes32 public curveData;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "MIRIN: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }
    
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        _;
    }

    modifier onlyOwner {
        require(msg.sender == masterContract.owner(), "MIRIN: FORBIDDEN");
        _;
    }

    /**
     * @notice The constructor is only used for the initial `masterContract`. Subsequent clones are initialized via `init()`
     */
    constructor(
        IBentoBoxV1 _bentoBox,
        address _masterFeeTo,
        address _owner
    ) {
        bentoBox = _bentoBox;
        masterContract = this;
        masterFeeTo = _masterFeeTo;
        owner = _owner;
    }

    /**
     * @notice Serves as the constructor for clones, as clones can't have a regular constructor
     * @dev `data` is abi-encoded in the format: (address tokenA, address tokenB, address _curve, bytes32 _curveData, uint8 _swapFee, address _swapFeeTo)
     */
    function init(bytes calldata data) external {
        require(address(token0) == address(0), 'MIRIN: ALREADY_INITIALIZED');
        (address tokenA, address tokenB, address _curve, bytes32 _curveData, uint8 _swapFee, address _swapFeeTo) = abi.decode(data, (address, address, address, bytes32, uint8, address));
        require(tokenA != tokenB, 'MIRIN: IDENTICAL_ADDRESSES');
        (address _token0, address _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(_token0 != address(0), 'MIRIN: ZERO_ADDRESS');
        require(masterContract.isCurveWhitelisted(_curve), "MIRIN: INVALID_CURVE");
        require(IMirinCurve(_curve).isValidData(_curveData), "MIRIN: INVALID_CURVE_DATA");
        require(_swapFee >= MIN_SWAP_FEE && _swapFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        masterContract.getPool(_token0, _token1) == address(this);
        masterContract.getPool(_token1, _token0) == address(this); // populate mapping in the reverse direction
        masterContract.pushPool(address(this));
        token0 = _token0;
        token1 = _token1;
        curve = _curve;
        curveData = _curveData;
        swapFee = _swapFee;
        swapFeeTo = _swapFeeTo;
        emit PoolCreated(_token0, _token1, address(this), masterContract.allPoolsLength());
    }

    function pushPool(address pool) external {
        allPools.push(pool);
    }

    function allPoolsLength() external view returns (uint256) {
        return masterContract.allPoolsLength();
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /// **** POOL FUNCTIONS ****
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "MIRIN: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        if (blockTimestamp != _blockTimestampLast && _reserve0 != 0 && _reserve1 != 0) {
            bytes32 _curveData = curveData;
            unchecked {
                uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
                uint256 price0 = IMirinCurve(curve).computePrice(_reserve0, _reserve1, _curveData, 0);
                price0CumulativeLast += price0 * timeElapsed;
                uint256 price1 = IMirinCurve(curve).computePrice(_reserve0, _reserve1, _curveData, 1);
                price1CumulativeLast += price1 * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;

        emit Sync(uint112(balance0), uint112(balance1));
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            bytes32 _curveData = curveData;
            uint256 computed = IMirinCurve(curve).computeLiquidity(_reserve0, _reserve1, _curveData);
            if (computed > _kLast) {
                uint256 numerator = totalSupply * (computed - _kLast);
                uint256 denominator = (computed * (swapFee * 2 - 1)) + _kLast; // 0.05% of increased liquidity
                uint256 liquidity = numerator / denominator;
                if (liquidity > 0) {
                    if (masterFeeTo == address(0)) {
                        _mint(masterContract.masterFeeTo(), liquidity * 2);
                    } else {
                        _mint(masterContract.masterFeeTo(), liquidity);
                        _mint(swapFeeTo, liquidity);
                    }
                }
            }
        }
    }

    function mint(address to) public lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        uint256 balance0 = bentoBox.balanceOf(IERC20(token0), address(this));
        uint256 balance1 = bentoBox.balanceOf(IERC20(token1), address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        bytes32 _curveData = curveData;
        uint256 computed = IMirinCurve(curve).computeLiquidity(uint112(balance0), uint112(balance1), _curveData);
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = computed - _totalSupply;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(address to) public lock returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = bentoBalance(IERC20(token0), IERC20(token1));
        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        _burn(liquidity, amount0, amount1, to);
    }

    function burn(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external lock {
        _burn(balanceOf[address(this)], amount0, amount1, to);
    }

    function _burn(
        uint256 liquidity,
        uint256 amount0,
        uint256 amount1,
        address to
    ) private {
        require(amount0 > 0 || amount1 > 0, "MIRIN: INVALID_AMOUNTS");

        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves();
        _mintFee(_reserve0, _reserve1);

        IERC20 _token0 = IERC20(token0);                                 // gas savings
        IERC20 _token1 = IERC20(token1);                                 // gas savings

        uint256 computed =
            IMirinCurve(curve).computeLiquidity(uint112(_reserve0 - amount0), uint112(_reserve1 - amount1), curveData);
        uint256 liquidityDelta = kLast - computed;
        require(liquidityDelta <= liquidity, "MIRIN: LIQUIDITY");
        if (liquidityDelta < liquidity) {
            _transfer(address(this), to, liquidity - liquidityDelta);
            liquidity = liquidityDelta;
        }
        _burn(address(this), liquidity);

        bentoBox.transfer(_token0, address(this), to, amount0);
        bentoBox.transfer(_token1, address(this), to, amount1);
        (uint256 balance0, uint256 balance1) = bentoBalance(IERC20(_token0), IERC20(_token0));

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function bentoBalance(IERC20 _token0, IERC20 _token1) private view returns (uint256 balance0, uint256 balance1) {
        balance0 = bentoBox.balanceOf(IERC20(_token0), address(this));
        balance1 = bentoBox.balanceOf(IERC20(_token1), address(this));
    }

    function computeCheck(uint256 amount0In, uint256 amount1In, uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private view {
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * swapFee;
        bytes32 _curveData = curveData;
        require(
            IMirinCurve(curve).computeLiquidity(uint112(balance0Adjusted), uint112(balance1Adjusted), _curveData) >=
            IMirinCurve(curve).computeLiquidity(_reserve0 * 1000, _reserve1 * 1000, _curveData),
            "MIRIN: LIQUIDITY"
        );
    }

    function _swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data, address _token0, address _token1) private {
        if (amount0Out > 0) bentoBox.transfer(IERC20(_token0), address(this), to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) bentoBox.transfer(IERC20(_token1), address(this), to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0Out, amount1Out, data);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = getReserves(); // gas savings
        { // scope for _token{0,1} avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(amount0Out > 0 || amount1Out > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(to != _token0 && to != _token1, "MIRIN: INVALID_TO");
        _swap(amount0Out, amount1Out, to, data, _token0, _token1);
        }
        uint256 amount0In;
        uint256 amount1In;
        { // scope for balance{0,1} avoids stack too deep errors
        (uint256 balance0, uint256 balance1) = bentoBalance(IERC20(token0), IERC20(token1));
        amount0In = balance0 + amount0Out - _reserve0;
        amount1In = balance1 + amount1Out - _reserve1;

        computeCheck(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        }
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    
    /// **** ADD LIQUIDITY ****
    function addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) lock returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        if (_reserve0 == 0 && _reserve1 == 0) {
            (amount0, amount1) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal  = amountADesired * (_reserve1 / _reserve0);
            if (amountBOptimal  <= amountBDesired) {
                require(amountBOptimal  >= amountBMin, 'MIRIN: INSUFFICIENT_B_AMOUNT');
                (amount0, amount1) = (amountADesired, amountBOptimal );
            } else {
                uint256 amountAOptimal = amountBDesired * (_reserve1 / _reserve0);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'MIRIN: INSUFFICIENT_A_AMOUNT');
                (amount0, amount1) = (amountAOptimal, amountBDesired);
            }
        }
        bentoBox.transfer(IERC20(token0), msg.sender, address(this), amount0);
        bentoBox.transfer(IERC20(token1), msg.sender, address(this), amount1);
        liquidity = mint(to);
    }
    
    /// **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) lock returns (uint amountA, uint amountB) {
        this.transferFrom(msg.sender, address(this), liquidity); // send liquidity to this pair
        (amountA, amountB) = burn(to);
        require(amountA >= amountAMin, 'MIRIN: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'MIRIN: INSUFFICIENT_B_AMOUNT');
    }

    function sync() external lock {
        (uint256 balance0, uint256 balance1) = bentoBalance(IERC20(token0), IERC20(token1));
        _update(balance0, balance1, reserve0, reserve1, blockTimestampLast);
    }

    /// **** MASTER GOVERNANCE ****
    function setMasterFeeTo(address _masterFeeTo) external onlyOwner {
        masterContract.masterFeeTo() == _masterFeeTo;
    }

    function setOwner(address _owner) external onlyOwner {
        masterContract.owner() == _owner;
    }

    function whitelistCurve(address _curve) external onlyOwner {
        masterContract.isCurveWhitelisted(_curve) == true;
    }
}

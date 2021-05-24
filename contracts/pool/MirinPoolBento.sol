// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../interfaces/IMirinFactory.sol";
import "./MirinERC20.sol";
import "../interfaces/IMirinCurve.sol";
import "../interfaces/IBentoBox.sol";

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
    event PoolDisabled(address indexed pool);
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
    event OperatorSet(address indexed previousOperator, address indexed newOperator);
    event SwapFeeUpdated(uint8 newFee);
    event SwapFeeToUpdated(address newFeeTo);

    uint8 public constant MIN_SWAP_FEE = 1;
    uint8 public constant MAX_SWAP_FEE = 100;

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public operator;
    /**
     * @dev Fee for swapping (out of 1000).
     */
    uint8 public swapFee;
    /**
     * @dev Swap fee receiver.
     */
    address public feeTo;

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

    modifier onlyOperator() {
        require(operator == msg.sender, "MIRIN: UNAUTHORIZED");
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
     * @dev `data` is abi-encoded in the format: (address tokenA, address tokenB, address _curve, bytes32 _curveData, uint8 _swapFee, address _feeTo)
     */
    function init(bytes calldata data) external {
        require(address(token0) == address(0), 'MIRIN: ALREADY_INITIALIZED');
        (address tokenA, address tokenB, address _curve, bytes32 _curveData, address _operator, uint8 _swapFee, address _feeTo) = abi.decode(data, (address, address, address, bytes32, address, uint8, address));
        require(tokenA != tokenB, 'MIRIN: IDENTICAL_ADDRESSES');
        (address _token0, address _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(_token0 != address(0), 'MIRIN: ZERO_ADDRESS');
        require(masterContract.isCurveWhitelisted(_curve), "MIRIN: INVALID_CURVE");
        require(IMirinCurve(_curve).isValidData(_curveData), "MIRIN: INVALID_CURVE_DATA");
        masterContract.getPool(_token0, _token1) == address(this);
        masterContract.getPool(_token1, _token0) == address(this); // populate mapping in the reverse direction
        masterContract.pushPool(address(this));
        token0 = _token0;
        token1 = _token1;
        curve = _curve;
        curveData = _curveData;
        operator = _operator; // placeholder for tests - this should resolve to LP token voting
        _updateSwapFee(_swapFee);
        _updateSwapFeeTo(_feeTo);
        emit PoolCreated(_token0, _token1, address(this), masterContract.allPoolsLength());
    }

    /// **** PUSH POOL ****
    function pushPool(address pool) external {
        allPools.push(pool);
    }

    /// **** GETTER FUNCTIONS ****
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
                        _mint(feeTo, liquidity);
                    }
                }
            }
        }
    }

    function mint(address to) external lock returns (uint256 liquidity) {
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

    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
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

    function sync() external lock {
        (uint256 balance0, uint256 balance1) = bentoBalance(IERC20(token0), IERC20(token1));
        _update(balance0, balance1, reserve0, reserve1, blockTimestampLast);
    }

    /// **** POOL GOVERNANCE ****
    function _updateSwapFee(uint8 newFee) internal {
        require(newFee >= MIN_SWAP_FEE && newFee <= MAX_SWAP_FEE, "MIRIN: INVALID_SWAP_FEE");
        swapFee = newFee;
        emit SwapFeeUpdated(newFee);
    }

    function _updateSwapFeeTo(address newFeeTo) internal {
        feeTo = newFeeTo;
        emit SwapFeeToUpdated(newFeeTo);
    }

    function setOperator(address newOperator) external onlyOperator {
        require(newOperator != address(0), "MIRIN: INVALID_OPERATOR");
        operator = newOperator;
        emit OperatorSet(operator, newOperator);
    }

    function updateCurveData(bytes32 data) external onlyOperator {
        require(IMirinCurve(curve).canUpdateData(curveData, data), "MIRIN: CANNOT_UPDATE_DATA");
        curveData = data;
    }

    function updateSwapFee(uint8 newFee) public onlyOperator {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        _mintFee(_reserve0, _reserve1);
        _updateSwapFee(newFee);
    }

    function updateSwapFeeTo(address newFeeTo) public onlyOperator {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        _mintFee(_reserve0, _reserve1);
        _updateSwapFeeTo(newFeeTo);
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

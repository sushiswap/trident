// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinGovernance.sol";
import "../interfaces/IMirinCurve.sol";

/**
 * @author LevX
 */
contract MirinPool is MirinGovernance {
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

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public immutable token0;
    address public immutable token1;
    address public immutable curve;

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

    modifier enabled() {
        require(IMirinFactory(factory).isPool(address(this)), "MIRIN: DISABLED_POOL");
        _;
    }

    constructor(
        address _token0,
        address _token1,
        address _curve,
        bytes32 _curveData,
        address _operator,
        uint8 _swapFee,
        address _swapFeeTo
    ) MirinGovernance(_operator, _swapFee, _swapFeeTo) {
        require(IMirinCurve(_curve).isValidData(_curveData), "MIRIN: INVALID_CURVE_DATA");
        token0 = _token0;
        token1 = _token1;
        curve = _curve;
        curveData = _curveData;
    }

    function initialize(address, address) external pure {
        revert("MIRIN: NOT_IMPLEMENTED");
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

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "MIRIN: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed;
        unchecked {timeElapsed = blockTimestamp - blockTimestampLast;}
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            bytes32 _curveData = curveData;
            unchecked {
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

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "MIRIN: TRANSFER_FAILED");
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
                    if (swapFeeTo == address(0)) {
                        _mint(IMirinFactory(factory).feeTo(), liquidity * 2);
                    } else {
                        _mint(IMirinFactory(factory).feeTo(), liquidity);
                        _mint(swapFeeTo, liquidity);
                    }
                }
            }
        }
    }

    function mint(address to) external lock enabled onlyWhitelisted(to) returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
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
            uint256 k = IMirinCurve(curve).computeLiquidity(uint112(_reserve0), uint112(_reserve1), _curveData);
            liquidity = (computed - k) * _totalSupply / k;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(address to) external lock onlyWhitelisted(to) returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        _mintFee(_reserve0, _reserve1);
        uint256 liquidity = balanceOf[address(this)];
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = IMirinCurve(curve).computeLiquidity(uint112(balance0), uint112(balance1), curveData);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function burn(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external lock onlyWhitelisted(to) {
        require(amount0 > 0 || amount1 > 0, "MIRIN: INVALID_AMOUNTS");

        uint256 liquidity = balanceOf[address(this)];
        
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        _mintFee(_reserve0, _reserve1);

        bytes32 _curveData = curveData;
        uint256 k = IMirinCurve(curve).computeLiquidity(uint112(_reserve0), uint112(_reserve1), _curveData);
        uint256 computed =
            IMirinCurve(curve).computeLiquidity(uint112(_reserve0 - amount0), uint112(_reserve1 - amount1), _curveData);
        uint256 liquidityDelta = (k - computed) * totalSupply / k;

        require(liquidityDelta <= liquidity, "MIRIN: LIQUIDITY");
        if (liquidityDelta < liquidity) {
            _transfer(address(this), to, liquidity - liquidityDelta);
            liquidity = liquidityDelta;
        }
        _burn(address(this), liquidity);

        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = computed;
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata
    ) external {
        swap(amount0Out, amount1Out, to);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) public lock enabled onlyWhitelisted(to) {
        require(amount0Out > 0 || amount1Out > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "MIRIN: INSUFFICIENT_LIQUIDITY");

        require(to != token0 && to != token1, "MIRIN: INVALID_TO");
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        {
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * swapFee;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * swapFee;
            bytes32 _curveData = curveData;
            require(
                IMirinCurve(curve).computeLiquidity(balance0Adjusted, balance1Adjusted, _curveData) >=
                    IMirinCurve(curve).computeLiquidity(_reserve0 * 1000, _reserve1 * 1000, _curveData),
                "MIRIN: LIQUIDITY"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function skim(address to) external lock {
        _safeTransfer(token0, to, IERC20(token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(token1, to, IERC20(token1).balanceOf(address(this)) - reserve1);
    }

    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinOptions.sol";
import "./MirinERC20.sol";
import "./MirinGovernance.sol";

/**
 * @author LevX
 */
contract MirinPool is MirinOptions, MirinERC20, MirinGovernance {
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

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    uint256 public kLast;

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
        uint8 _weight0,
        uint8 _weight1,
        address _operator,
        uint8 _swapFee,
        address _swapFeeTo
    ) MirinOptions(_token0, _token1, _weight0, _weight1) MirinGovernance(_operator, _swapFee, _swapFeeTo) {}

    function initialize(address, address) external {
        revert("MIRIN: NOT_IMPLEMENTED");
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
            (uint8 _weight0, uint8 _weight1) = (weight0, weight1);
            uint256 rootK =
                MirinMath.root(uint256(_reserve0)**_weight0 * uint256(_reserve1)**_weight1, _weight0 + _weight1);
            uint256 rootKLast = MirinMath.root(_kLast, _weight0 + _weight1);
            if (rootK > rootKLast) {
                uint256 numerator = totalSupply * (rootK - rootKLast);
                uint256 denominator = (rootK * (swapFee * 2 - 1)) + rootKLast; // 0.05% of increased liquidity
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

    function mint(address to) external lock enabled notBlacklisted(to) returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        (uint8 _weight0, uint8 _weight1) = (weight0, weight1);
        uint256 k = balance0**_weight0 * balance1**_weight1;
        if (_totalSupply == 0) {
            liquidity = MirinMath.root(k, _weight0 + _weight1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = MirinMath.root(k, _weight0 + _weight1) - _totalSupply;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = k;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        return burn(0, 0, to);
    }

    function burn(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) public lock notBlacklisted(to) returns (uint256 amount0, uint256 amount1) {
        return _burn(amount0Out, amount1Out, to);
    }

    function _burn(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) private returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        amount0 = amount0Out == 0 ? (liquidity * balance0) / _totalSupply : amount0Out;
        amount1 = amount1Out == 0 ? (liquidity * balance1) / _totalSupply : amount1Out;
        require(amount0 > 0 && amount1 > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_BURNED");
        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        (uint8 _weight0, uint8 _weight1) = (weight0, weight1);
        uint256 k = balance0**_weight0 * balance1**_weight1;
        uint256 rootK = MirinMath.root(k, _weight0 + _weight1);
        uint256 rootKDelta = MirinMath.root(kLast, _weight0 + _weight1) - rootK;
        if (rootKDelta > 0 && rootKDelta < liquidity) {
            _transfer(address(this), to, liquidity - rootKDelta);
            liquidity -= rootKDelta;
        }
        _burn(address(this), liquidity);
        require(rootK == totalSupply, "MIRIN: K");

        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = k;
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
    ) public lock enabled notBlacklisted(to) {
        require(amount0Out > 0 || amount1Out > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "MIRIN: INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        {
            require(to != token0 && to != token1, "MIRIN: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);
            balance0 = IERC20(token0).balanceOf(address(this));
            balance1 = IERC20(token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        {
            (uint8 _weight0, uint8 _weight1) = (weight0, weight1);
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * swapFee;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * swapFee;
            require(
                balance0Adjusted**_weight0 * balance1Adjusted**_weight1 >=
                    uint256(_reserve0 * 1000)**_weight0 * uint256(_reserve1 * 1000)**_weight1,
                "MIRIN: K"
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

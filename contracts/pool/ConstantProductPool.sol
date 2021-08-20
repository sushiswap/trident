// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "../libraries/TridentMath.sol";
import "../libraries/RebaseLibrary.sol";
import "./TridentERC20.sol";
import "../workInProgress/IMigrator.sol";
import "../deployer/MasterDeployer.sol";

/// @notice Trident exchange pool template with constant product formula for swapping between an ERC-20 token pair.
/// @dev The reserves are stored as bento shares.
///      The curve is applied to shares as well. This pool does not care about the underlying amounts.
contract ConstantProductPool is IPool, TridentERC20 {
    using RebaseLibrary for Rebase;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Sync(uint256 reserveShares0, uint256 reserveShares4);

    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    uint8 internal constant PRECISION = 112;
    uint256 internal constant MAX_FEE = 10000; // @dev 100%.
    uint256 internal constant MAX_FEE_SQUARE = 100000000;
    uint256 public immutable swapFee;
    uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE;

    address public immutable barFeeTo;
    address public immutable bento;
    address public immutable masterDeployer;
    address public immutable token0;
    address public immutable token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint112 internal reserveShares0;
    uint112 internal reserveShares1;
    uint32 internal blockTimestampLast;

    bytes32 public constant override poolIdentifier = "Trident:ConstantProduct";

    uint256 private unlocked;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    struct Holdings {
        uint256 shares0;
        uint256 shares1;
        uint256 amount0;
        uint256 amount1;
    }

    struct Rebases {
        Rebase total0;
        Rebase total1;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address tokenA, address tokenB, uint256 _swapFee, bool _twapSupport) = abi.decode(
            _deployData,
            (address, address, uint256, bool)
        );

        require(tokenA != address(0), "ZERO_ADDRESS");
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "INVALID_SWAP_FEE");

        (, bytes memory _bento) = _masterDeployer.staticcall(abi.encodeWithSelector(0x4da31827)); // @dev bento().
        (, bytes memory _barFeeTo) = _masterDeployer.staticcall(abi.encodeWithSelector(0x0c0a0cd2)); // @dev barFeeTo().

        token0 = tokenA;
        token1 = tokenB;
        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = abi.decode(_bento, (address));
        barFeeTo = abi.decode(_barFeeTo, (address));
        masterDeployer = _masterDeployer;
        unlocked = 1;
        if (_twapSupport) {
            blockTimestampLast = 1;
        }
    }

    function mint(bytes calldata data) public override lock returns (uint256 liquidity) {
        address to = abi.decode(data, (address));
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 _totalSupply = totalSupply;

        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 computed = TridentMath.sqrt(balances.amount0 * balances.amount1);
        if (_totalSupply == 0) {
            _mint(address(0), MINIMUM_LIQUIDITY);
            address migrator = MasterDeployer(masterDeployer).migrator();
            if (msg.sender == migrator) {
                liquidity = IMigrator(migrator).desiredLiquidity();
                require(liquidity > 0 && liquidity != type(uint256).max, "BAD_DESIRED_LIQUIDITY");
            } else {
                require(migrator == address(0), "ONLY_MIGRATOR");
                liquidity = computed - MINIMUM_LIQUIDITY;
            }
        } else {
            uint256 k = TridentMath.sqrt(reserves.amount0 * reserves.amount1);
            liquidity = ((computed - k) * _totalSupply) / k;
        }
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(reserves, balances, _blockTimestampLast);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(bytes calldata data) public override lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (address to, bool unwrapBento) = abi.decode(data, (address, bool));
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 _totalSupply = totalSupply;
        uint256 liquidity = balanceOf[address(this)];

        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        _transferShares(token0, shares0, to, unwrapBento);
        _transferShares(token1, shares1, to, unwrapBento);

        balances.shares0 -= shares0;
        balances.shares1 -= shares1;
        balances.amount0 = rebase.total0.toElastic(balances.shares0);
        balances.amount1 = rebase.total1.toElastic(balances.shares1);

        _update(reserves, balances, _blockTimestampLast);
        kLast = TridentMath.sqrt(balances.amount0 * balances.amount1);

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: address(token0), amount: amount0});
        withdrawnAmounts[1] = TokenAmount({token: address(token1), amount: amount1});

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function burnSingle(bytes calldata data) public override lock returns (uint256 amount) {
        (address tokenOut, address to, bool unwrapBento) = abi.decode(data, (address, address, bool));
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 _totalSupply = totalSupply;
        uint256 liquidity = balanceOf[address(this)];

        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        if (tokenOut == token1) {
            // @dev Swap token0 for token1.
            // Calculate amountOut as if the user first withdrew balanced liquidity and then swapped token0 for token1.
            amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1);
            _transfer(token1, amount1, to, unwrapBento);
            balance1 -= amount1;
            amount = amount1;
            amount0 = 0;
        } else {
            // @dev Swap token1 for token0.
            require(tokenOut == token1, "INVALID_OUTPUT_TOKEN");
            amount0 += _getAmountOut(amount1, _reserve1 - amount1, _reserve0 - amount0);
            _transfer(token0, amount0, to, unwrapBento);
            balance0 -= amount0;
            amount = amount0;
            amount1 = 0;
        }

        _update(reserves, balances, _blockTimestampLast);
        kLast = TridentMath.sqrt(balances.amount0 * balances.amount1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (address tokenIn, address recipient, bool unwrapBento) = abi.decode(data, (address, address, bool));
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amountIn;
        address tokenOut;

        if (tokenIn == token0) {
            tokenOut = token1;
            amountIn = balance0 - _reserve0;
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            balance1 -= amountOut;
        } else {
            require(tokenIn == token1, "INVALID_INPUT_TOKEN");
            tokenOut = token0;
            amountIn = balance1 - reserve1;
            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            balance0 -= amountOut;
        }
        _transfer(tokenOut, amountOut, recipient, unwrapBento);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function flashSwap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (address tokenIn, address recipient, bool unwrapBento, uint256 amountIn, bytes memory context) = abi.decode(
            data,
            (address, address, bool, uint256, bytes)
        );
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();

        if (tokenIn == token0) {
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            _transfer(token1, amountOut, recipient, unwrapBento);
            ITridentCallee(msg.sender).tridentSwapCallback(context);
            (uint256 balance0, uint256 balance1) = _balance();
            require(balance0 - _reserve0 >= amountIn, "INSUFFICIENT_AMOUNT_IN");
            _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
            emit Swap(recipient, tokenIn, token1, amountIn, amountOut);
        } else {
            require(tokenIn == token1, "INVALID_INPUT_TOKEN");
            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            _transfer(token0, amountOut, recipient, unwrapBento);
            ITridentCallee(msg.sender).tridentSwapCallback(context);
            (uint256 balance0, uint256 balance1) = _balance();
            require(balance1 - _reserve1 >= amountIn, "INSUFFICIENT_AMOUNT_IN");
            _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
            emit Swap(recipient, tokenIn, token0, amountIn, amountOut);
        }
    }

    function _getReserves()
        internal
        view
        returns (
            Holdings memory _reserves,
            uint32 _blockTimestampLast,
            Rebases memory _rebase
        )
    {
        _reserves.shares0 = reserveShares0;
        _reserves.shares1 = reserveShares1;
        _blockTimestampLast = blockTimestampLast;
        _rebase.total0 = bento.totals(token0);
        _rebase.total1 = bento.totals(token1);
        _reserves.amount0 = _rebase.total0.toElastic(_reserves.shares0);
        _reserves.amount1 = _rebase.total1.toElastic(_reserves.shares1);
    }

    function _balance(Rebases memory _rebase) internal view returns (Holdings memory _balances) {
        _balances.shares0 = bento.balanceOf(token0, address(this));
        _balances.shares1 = bento.balanceOf(token1, address(this));
        _balances.amount0 = _rebase.total0.toElastic(_balances.shares0);
        _balances.amount1 = _rebase.total1.toElastic(_balances.shares1);
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        // @dev balanceOf(address,address).
        (, bytes memory _balance0) = bento.staticcall(abi.encodeWithSelector(0xf7888aec, token0, address(this)));
        balance0 = abi.decode(_balance0, (uint256));
        // @dev balanceOf(address,address).
        (, bytes memory _balance1) = bento.staticcall(abi.encodeWithSelector(0xf7888aec, token1, address(this)));
        balance1 = abi.decode(_balance1, (uint256));
    }

    function _update(
        Holdings memory _reserves,
        Holdings memory _balances,
        uint32 _blockTimestampLast
    ) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OVERFLOW");

        if (blockTimestampLast == 0) {
            // @dev TWAP support is disabled for gas efficiency.
            reserve0 = uint112(balance0);
            reserve1 = uint112(balance1);
        } else {
            uint32 blockTimestamp = uint32(block.timestamp % 2**32);
            if (blockTimestamp != _blockTimestampLast && _reserves.amount0 != 0 && _reserves.amount1 != 0) {
                unchecked {
                    uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
                    uint256 price0 = (_reserves.amount1 << PRECISION) / _reserves.amount0;
                    price0CumulativeLast += price0 * timeElapsed;
                    uint256 price1 = (_reserves.amount0 << PRECISION) / _reserves.amount1;
                    price1CumulativeLast += price1 * timeElapsed;
                }
            }
            reserveShares0 = uint112(_balances.shares0);
            reserveShares1 = uint112(_balances.shares1);
            blockTimestampLast = blockTimestamp;
        }

        emit Sync(_balances.amount0, _balances.amount1);
    }

    function _mintFee(
        uint256 _reserveAmount0,
        uint256 _reserveAmount1,
        uint256 _totalSupply
    ) internal returns (uint256 computed) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            computed = TridentMath.sqrt(_reserveAmount0 * _reserveAmount1);
            if (computed > _kLast) {
                // @dev 'barFee' % of increase in liquidity.
                // It's going to be slightly less than barFee % in reality due to the math.
                (, bytes memory _barFee) = masterDeployer.staticcall(abi.encodeWithSelector(0xc14ad802)); // @dev barFee().
                uint256 barFee = abi.decode(_barFee, (uint256));
                uint256 liquidity = (_totalSupply * (computed - _kLast) * barFee) / computed / MAX_FEE;
                if (liquidity != 0) {
                    _mint(barFeeTo, liquidity);
                }
            }
        }
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveAmountIn,
        uint256 reserveAmountOut
    ) internal view returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * MAX_FEE_MINUS_SWAP_FEE;
        amountOut = (amountInWithFee * reserveAmountOut) / (reserveAmountIn * MAX_FEE + amountInWithFee);
    }

    function _transferShares(
        address token,
        uint256 shares,
        address to,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            // @dev withdraw(address,address,address,uint256,uint256).
            (bool success, ) = bento.call(abi.encodeWithSelector(0x97da6d30, token, address(this), to, 0, shares));
            require(success, "WITHDRAW_FAILED");
        } else {
            // @dev transfer(address,address,address,uint256).
            (bool success, ) = bento.call(abi.encodeWithSelector(0xf18d03cc, token, address(this), to, shares));
            require(success, "TRANSFER_FAILED");
        }
    }

    function getAssets() public view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    function getAmountOut(bytes calldata data) public view override returns (uint256 finalAmountOut) {
        (address tokenIn, uint256 amountIn) = abi.decode(data, (address, uint256));
        (uint112 _reserve0, uint112 _reserve1, ) = _getReserves();
        if (tokenIn == token0) {
            finalAmountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
        } else {
            finalAmountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
        }
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
        return _getReserves();
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../deployer/MasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IMigrator.sol";
import "../interfaces/ITridentCallee.sol";
import "../libraries/TridentMath.sol";
import "../libraries/RebaseLibrary.sol";
import "./TridentERC20.sol";
import "hardhat/console.sol";

/// @notice Trident exchange pool template with constant product formula for swapping between an ERC-20 token pair.
/// @dev The reserves are stored as bento shares. However, the constant product curve is applied to the underlying amounts.
///      The API uses the underlying amounts.
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
    IBentoBoxMinimal public immutable bento;
    MasterDeployer public immutable masterDeployer;
    address public immutable token0;
    address public immutable token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint112 internal reserveShares0;
    uint112 internal reserveShares1;
    uint32 internal blockTimestampLast;

    bytes32 public constant override poolIdentifier = "Trident:ConstantProduct";

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "MIRIN: LOCKED");
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

        require(tokenA != address(0), "ConstantProductPoolWithTWAP: ZERO_ADDRESS");
        require(tokenA != tokenB, "ConstantProductPoolWithTWAP: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "ConstantProductPoolWithTWAP: INVALID_SWAP_FEE");

        token0 = tokenA;
        token1 = tokenB;
        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxMinimal(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
        if (_twapSupport) {
            blockTimestampLast = 1;
        }
    }

    function mint(bytes calldata data) public override lock returns (uint256 liquidity) {
        address to = abi.decode(data, (address));
        (Holdings memory reserves, uint32 _blockTimestampLast, Rebases memory rebase) = _getReserves();
        Holdings memory balances = _balance(rebase);
        uint256 _totalSupply = totalSupply;
        _mintFee(reserves.amount0, reserves.amount1, _totalSupply);

        uint256 amount0 = balances.amount0 - reserves.amount0;
        uint256 amount1 = balances.amount1 - reserves.amount1;

        uint256 computed = TridentMath.sqrt(balances.amount0 * balances.amount1);
        if (_totalSupply == 0) {
            address migrator = masterDeployer.migrator();
            if (msg.sender == migrator) {
                liquidity = IMigrator(migrator).desiredLiquidity();
                require(liquidity > 0 && liquidity != type(uint256).max, "Bad desired liquidity");
            } else {
                require(migrator == address(0), "Must not have migrator");
                liquidity = computed - MINIMUM_LIQUIDITY;
                _mint(address(0), MINIMUM_LIQUIDITY);
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
        (Holdings memory reserves, uint32 _blockTimestampLast, Rebases memory rebase) = _getReserves();
        Holdings memory balances = _balance(rebase);
        uint256 _totalSupply = totalSupply;
        _mintFee(reserves.amount0, reserves.amount1, _totalSupply);
        uint256 liquidity = balanceOf[address(this)];

        uint256 shares0 = (liquidity * balances.shares0) / _totalSupply;
        uint256 shares1 = (liquidity * balances.shares1) / _totalSupply;
        uint256 amount0 = rebase.total0.toElastic(shares0);
        uint256 amount1 = rebase.total0.toElastic(shares1);

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
        (Holdings memory reserves, uint32 _blockTimestampLast, Rebases memory rebase) = _getReserves();
        Holdings memory balances = _balance(rebase);
        uint256 _totalSupply = totalSupply;
        _mintFee(reserves.amount0, reserves.amount1, _totalSupply);

        uint256 shares0;
        uint256 shares1;
        {
            uint256 liquidity = balanceOf[address(this)];
            shares0 = (liquidity * balances.shares0) / _totalSupply;
            shares1 = (liquidity * balances.shares1) / _totalSupply;
            _burn(address(this), liquidity);
        }
        uint256 amount0 = rebase.total0.toElastic(shares0);
        uint256 amount1 = rebase.total1.toElastic(shares1);

        if (tokenOut == address(token1)) {
            // @dev Swap token0 for token1.
            // @dev Calculate amountOut as if the user first withdrew balanced liquidity and then swapped token1 for token0.
            uint256 swapAmount1 = _getAmountOut(amount0, reserves.amount0 - amount0, reserves.amount1 - amount1);
            shares1 += rebase.total1.toBase(swapAmount1);
            amount1 += swapAmount1;
            amount0 = 0;
            balances.amount1 -= amount1;
            balances.shares1 -= shares1;
            amount = amount1;
            _transferShares(token1, shares1, to, unwrapBento);
        } else {
            // @dev Swap token1 for token0.
            // @dev Calculate amountOut as if the user first withdrew balanced liquidity and then swapped token1 for token0.
            require(tokenOut == address(token0), "INVALID_OUTPUT_TOKEN");
            uint256 swapAmount0 = _getAmountOut(amount1, reserves.amount1 - amount1, reserves.amount0 - amount0);
            shares0 += rebase.total0.toBase(swapAmount0);
            amount0 += swapAmount0;
            amount1 = 0;
            balances.amount0 -= amount0;
            balances.shares0 -= shares0;
            amount = amount0;
            _transferShares(token0, shares0, to, unwrapBento);
        }

        _update(reserves, balances, _blockTimestampLast);
        kLast = TridentMath.sqrt(balances.amount0 * balances.amount1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (address tokenIn, address recipient, bool unwrapBento) = abi.decode(data, (address, address, bool));
        (Holdings memory reserves, uint32 _blockTimestampLast, Rebases memory rebase) = _getReserves();
        Holdings memory balances = _balance(rebase);
        uint256 amountIn;
        address tokenOut;
        uint256 sharesOut;

        if (tokenIn == address(token0)) {
            tokenOut = token1;
            amountIn = balances.amount0 - reserves.amount0;
            amountOut = _getAmountOut(amountIn, reserves.amount0, reserves.amount1);
            sharesOut = rebase.total1.toBase(amountOut);
            balances.amount1 -= amountOut;
            balances.shares1 -= sharesOut;
        } else {
            require(tokenIn == address(token1), "INVALID_INPUT_TOKEN");
            tokenOut = token0;
            amountIn = balances.amount1 - reserves.amount1;
            amountOut = _getAmountOut(amountIn, reserves.amount1, reserves.amount0);
            sharesOut = rebase.total0.toBase(amountOut);
            balances.amount0 -= amountOut;
            balances.shares0 -= sharesOut;
        }
        _transferShares(tokenOut, sharesOut, recipient, unwrapBento);
        _update(reserves, balances, _blockTimestampLast);
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function flashSwap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (address tokenIn, address recipient, bool unwrapBento, uint256 amountIn, bytes memory context) = abi.decode(
            data,
            (address, address, bool, uint256, bytes)
        );
        (Holdings memory reserves, uint32 _blockTimestampLast, Rebases memory rebase) = _getReserves();
        address tokenOut;
        Holdings memory balances;

        if (tokenIn == address(token0)) {
            tokenOut = token1;
            amountOut = _getAmountOut(amountIn, reserves.amount0, reserves.amount1);
            {
                uint256 sharesOut = rebase.total1.toBase(amountOut);
                _transferShares(tokenOut, sharesOut, recipient, unwrapBento);
            }
            ITridentCallee(recipient).tridentCallback(tokenIn, tokenOut, amountIn, amountOut, context);
            balances = _balance(rebase);
            require(balances.amount0 - reserves.amount0 >= amountIn, "INSUFFICIENT_AMOUNT_IN");
        } else {
            require(tokenIn == address(token1), "INVALID_INPUT_TOKEN");
            tokenOut = token0;
            amountOut = _getAmountOut(amountIn, reserves.amount1, reserves.amount0);
            {
                uint256 sharesOut = rebase.total0.toBase(amountOut);
                _transferShares(tokenOut, sharesOut, recipient, unwrapBento);
            }
            ITridentCallee(recipient).tridentCallback(tokenIn, tokenOut, amountIn, amountOut, context);
            balances = _balance(rebase);
            require(balances.amount1 - reserves.amount1 >= amountIn, "INSUFFICIENT_AMOUNT_IN");
        }
        _update(reserves, balances, _blockTimestampLast);
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
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

    function _update(
        Holdings memory _reserves,
        Holdings memory _balances,
        uint32 _blockTimestampLast
    ) internal {
        require(_balances.shares0 <= type(uint112).max && _balances.shares1 <= type(uint112).max, "SAHRES_OVERFLOW");
        require(_balances.amount0 < type(uint128).max && _balances.amount1 < type(uint128).max, "AMOUNT_OVERFLOW");

        if (_blockTimestampLast == 0) {
            // TWAP support is disabled for gas efficiency
            reserveShares0 = uint112(_balances.shares0);
            reserveShares1 = uint112(_balances.shares1);
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
                // @dev barFee % of increase in liquidity.
                // @dev NB It's going to be slightly less than barFee % in reality due to the Math.
                uint256 barFee = MasterDeployer(masterDeployer).barFee();
                uint256 liquidity = (_totalSupply * (computed - _kLast) * barFee) / computed / MAX_FEE;
                if (liquidity > 0) {
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
            bento.withdraw(token, address(this), to, 0, shares);
        } else {
            bento.transfer(token, address(this), to, shares);
        }
    }

    function getAssets() public view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    function getAmountOut(bytes calldata data) public view override returns (uint256 finalAmountOut) {
        (address tokenIn, uint256 amountIn) = abi.decode(data, (address, uint256));
        (Holdings memory reserves, , ) = _getReserves();
        if (tokenIn == address(token0)) {
            finalAmountOut = _getAmountOut(amountIn, reserves.amount0, reserves.amount1);
        } else {
            finalAmountOut = _getAmountOut(amountIn, reserves.amount1, reserves.amount0);
        }
    }

    function getReserves()
        public
        view
        returns (
            Holdings memory,
            uint32,
            Rebases memory
        )
    {
        return _getReserves();
    }
}

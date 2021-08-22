// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../deployer/MasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "../libraries/MathUtils.sol";
import "./TridentERC20.sol";

/// @notice Trident exchange pool template with hybrid like-kind formula for swapping between an ERC-20 token pair.
/// @dev The reserves are stored as bento shares. However, the stabeswap invariant is applied to the underlying amounts.
///      The API uses the underlying amounts.
contract HybridPool is IPool, TridentERC20 {
    using MathUtils for uint256;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Sync(uint256 reserve0, uint256 reserve1);

    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;
    uint8 internal constant PRECISION = 112;

    /// @dev Constant value used as max loop limit.
    uint256 private constant MAX_LOOP_LIMIT = 256;
    uint256 internal constant MAX_FEE = 10000; // @dev 100%.
    uint256 public immutable swapFee;

    address public immutable barFeeTo;
    IBentoBoxMinimal public immutable bento;
    MasterDeployer public immutable masterDeployer;

    address public immutable token0;
    address public immutable token1;
    uint256 public immutable A;
    uint256 internal immutable N_A; // @dev 2 * A.
    uint256 internal constant A_PRECISION = 100;

    /// @dev Multipliers for each pooled token's precision to get to POOL_PRECISION_DECIMALS.
    /// For example, TBTC has 18 decimals, so the multiplier should be 1. WBTC
    /// has 8, so the multiplier should be 10 ** 18 / 10 ** 8 => 10 ** 10.
    uint256 public immutable token0PrecisionMultiplier;
    uint256 public immutable token1PrecisionMultiplier;

    uint128 internal reserve0;
    uint128 internal reserve1;

    bytes32 public constant override poolIdentifier = "Trident:HybridPair";

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "HybridPool: LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address tokenA, address tokenB, uint256 _swapFee, uint256 a) = abi.decode(_deployData, (address, address, uint256, uint256));

        require(tokenA != address(0), "HybridPool: ZERO_ADDRESS");
        require(tokenA != tokenB, "HybridPool: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "HybridPool: INVALID_SWAP_FEE");
        require(a != 0, "HybridPool: ZERO_A");

        token0 = tokenA;
        token1 = tokenB;
        swapFee = _swapFee;
        bento = IBentoBoxMinimal(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        A = a;
        N_A = 2 * a;
        token0PrecisionMultiplier = uint256(10)**(decimals - TridentERC20(tokenA).decimals());
        token1PrecisionMultiplier = uint256(10)**(decimals - TridentERC20(tokenB).decimals());
        unlocked = 1;
    }

    function mint(bytes calldata data) public override lock returns (uint256 liquidity) {
        address to = abi.decode(data, (address));
        (uint256 _reserve0, uint256 _reserve1) = _reserve();
        uint256 _totalSupply = totalSupply;
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 newLiq = _computeLiquidity(balance0, balance1);
        if (_totalSupply == 0) {
            liquidity = newLiq - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 oldLiq = _computeLiquidity(_reserve0, _reserve1);
            liquidity = ((newLiq - oldLiq) * _totalSupply) / oldLiq;
        }
        require(liquidity > 0, "HybridPool: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _updateReserves();
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(bytes calldata data) public override lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (address to, bool unwrapBento) = abi.decode(data, (address, bool));
        uint256 _totalSupply = totalSupply;

        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        _transferAmount(token0, to, amount0, unwrapBento);
        _transferAmount(token1, to, amount1, unwrapBento);

        balance0 -= bento.toShare(token0, amount0, false);
        balance1 -= bento.toShare(token1, amount1, false);

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: address(token0), amount: amount0});
        withdrawnAmounts[1] = TokenAmount({token: address(token1), amount: amount1});

        _updateReserves();
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function burnSingle(bytes calldata data) public override lock returns (uint256 amount) {
        (address tokenOut, address to, bool unwrapBento) = abi.decode(data, (address, address, bool));
        (uint256 _reserve0, uint256 _reserve1) = _reserve();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 _totalSupply = totalSupply;
        uint256 liquidity = balanceOf[address(this)];

        _burn(address(this), liquidity);

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        if (tokenOut == address(token1)) {
            // @dev Swap token0 for token1.
            // @dev Calculate amountOut as if the user first withdrew balanced liquidity and then swapped token0 for token1.
            uint256 fee = _handleFee(token0, amount0);
            amount1 += _getAmountOut(amount0 - fee, _reserve0 - amount0, _reserve1 - amount1, true);
            _transferAmount(token1, to, amount1, unwrapBento);
            balance0 -= bento.toShare(token0, amount0, false);
            amount = amount1;
            amount0 = 0;
        } else {
            // @dev Swap token1 for token0.
            require(tokenOut == address(token1), "INVALID_OUTPUT_TOKEN");
            uint256 fee = _handleFee(token1, amount1);
            amount0 += _getAmountOut(amount1 - fee, _reserve0 - amount0, _reserve1 - amount1, false);
            _transferAmount(token0, to, amount0, unwrapBento);
            balance1 -= bento.toShare(token1, amount1, false);
            amount = amount0;
            amount1 = 0;
        }

        _updateReserves();
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(bytes calldata data) public override returns (uint256 finalAmountOut) {
        require(unlocked == 1, "LOCKED");
        (address tokenIn, address recipient, bool unwrapBento) = abi.decode(data, (address, address, bool));
        (uint256 _reserve0, uint256 _reserve1) = _reserve();
        (uint256 balance0, uint256 balance1) = _balance();
        address tokenOut;

        if (tokenIn == address(token0)) {
            uint256 amountIn = balance0 - _reserve0;
            uint256 fee = _handleFee(tokenIn, amountIn);
            finalAmountOut = _getAmountOut(amountIn - fee, _reserve0, _reserve1, true);
            tokenOut = token1;
        } else {
            require(tokenIn == address(token1), "HybridPool: Invalid input token");
            uint256 amountIn = balance1 - _reserve1;
            uint256 fee = _handleFee(tokenIn, amountIn);
            finalAmountOut = _getAmountOut(amountIn - fee, _reserve0, _reserve1, false);
            tokenOut = token0;
        }

        _transferAmount(tokenOut, recipient, finalAmountOut, unwrapBento);
        _updateReserves();
    }

    function flashSwap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (address tokenIn, address recipient, bool unwrapBento, uint256 amountIn, bytes memory context) = abi.decode(
            data,
            (address, address, bool, uint256, bytes)
        );
        (uint256 _reserve0, uint256 _reserve1) = _reserve();
        uint256 fee;

        if (tokenIn == address(token0)) {
            amountIn = bento.toAmount(token0, amountIn, false);
            fee = (amountIn * swapFee) / MAX_FEE;
            amountOut = _getAmountOut(amountIn - fee, _reserve0, _reserve1, true);
            _processSwap(token1, recipient, amountOut, context, unwrapBento);
            uint256 balance0 = bento.toAmount(token0, bento.balanceOf(token0, address(this)), false);
            require(balance0 - _reserve0 >= amountIn, "HybridPool: Insuffficient amount in");
        } else {
            require(tokenIn == address(token1), "HybridPool: Invalid input token");
            amountIn = bento.toAmount(token1, amountIn, false);
            fee = (amountIn * swapFee) / MAX_FEE;
            amountOut = _getAmountOut(amountIn - fee, _reserve0, _reserve1, false);
            _processSwap(token0, recipient, amountOut, context, unwrapBento);
            uint256 balance1 = bento.toAmount(token1, bento.balanceOf(token0, address(this)), false);
            require(balance1 - _reserve1 >= amountIn, "HybridPool: Insufficient amount in");
        }

        _transferAmount(tokenIn, barFeeTo, fee, false);
        _updateReserves();
    }

    function _transferAmount(
        address token,
        address to,
        uint256 amount,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token, address(this), to, amount, 0);
        } else {
            bento.transfer(token, address(this), to, bento.toShare(token, amount, false));
        }
    }

    function _transferShares(
        address token,
        address to,
        uint256 shares,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token, address(this), to, 0, shares);
        } else {
            bento.transfer(token, address(this), to, shares);
        }
    }

    function _processSwap(
        address tokenOut,
        address to,
        uint256 amountOut,
        bytes memory data,
        bool unwrapBento
    ) internal {
        _transferAmount(tokenOut, to, amountOut, unwrapBento);
        if (data.length != 0) ITridentCallee(msg.sender).tridentSwapCallback(data);
    }

    function _handleFee(address tokenIn, uint256 amountIn) internal returns (uint256 fee) {
        fee = (amountIn * swapFee) / MAX_FEE;
        uint256 barFee = (fee * masterDeployer.barFee()) / MAX_FEE;
        _transferAmount(tokenIn, barFeeTo, barFee, false);
    }

    function _updateReserves() internal {
        uint256 _reserve0 = bento.balanceOf(token0, address(this));
        uint256 _reserve1 = bento.balanceOf(token1, address(this));
        require(_reserve0 < type(uint128).max && _reserve1 < type(uint128).max, "HybridPool: OVERFLOW");
        reserve0 = uint128(_reserve0);
        reserve1 = uint128(_reserve1);
        emit Sync(_reserve0, _reserve1);
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = bento.toAmount(token0, bento.balanceOf(token0, address(this)), false);
        balance1 = bento.toAmount(token1, bento.balanceOf(token1, address(this)), false);
    }

    function _reserve() internal view returns (uint256 _reserve0, uint256 _reserve1) {
        (_reserve0, _reserve1) = (reserve0, reserve1);
        _reserve0 = bento.toAmount(token0, _reserve0, false);
        _reserve1 = bento.toAmount(token1, _reserve1, false);
    }

    function getAmountOut(bytes calldata data) public view override returns (uint256 finalAmountOut) {
        (address tokenIn, uint256 amountIn) = abi.decode(data, (address, uint256));
        (uint256 _reserve0, uint256 _reserve1) = _reserve();
        amountIn = bento.toAmount(tokenIn, amountIn, false);
        amountIn -= (amountIn * swapFee) / MAX_FEE;
        if (tokenIn == token0) {
            finalAmountOut = _getAmountOut(amountIn, _reserve0, _reserve1, true);
        } else {
            finalAmountOut = _getAmountOut(amountIn, _reserve0, _reserve1, false);
        }
    }

    function getAssets() public view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    /**
     * @notice Get D, the StableSwap invariant, based on a set of balances and a particular A.
     * See the StableSwap paper for details
     *
     * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L319
     *
     * @return the invariant, at the precision of the pool
     */
    function _computeLiquidity(uint256 _reserve0, uint256 _reserve1) internal view returns (uint256) {
        uint256 xp0 = _reserve0 * token0PrecisionMultiplier;
        uint256 xp1 = _reserve1 * token1PrecisionMultiplier;

        return _computeLiquidityFromAdjustedBalances(xp0, xp1);
    }

    function _computeLiquidityFromAdjustedBalances(uint256 xp0, uint256 xp1) internal view returns (uint256) {
        uint256 s = xp0 + xp1;

        if (s == 0) {
            return 0;
        }

        uint256 prevD;
        uint256 D = s;
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            uint256 dP = (((D * D) / xp0) * D) / xp1 / 4;
            prevD = D;
            D = (((N_A * s) / A_PRECISION + 2 * dP) * D) / ((N_A / A_PRECISION - 1) * D + 3 * dP);
            if (D.within1(prevD)) {
                break;
            }
        }
        return D;
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 _reserve0,
        uint256 _reserve1,
        bool token0In
    ) public view returns (uint256) {
        uint256 xpIn;
        uint256 xpOut;

        if (token0In) {
            xpIn = _reserve0 * token0PrecisionMultiplier;
            xpOut = _reserve1 * token1PrecisionMultiplier;
            amountIn *= token0PrecisionMultiplier;
        } else {
            xpIn = _reserve1 * token1PrecisionMultiplier;
            xpOut = _reserve0 * token0PrecisionMultiplier;
            amountIn *= token1PrecisionMultiplier;
        }

        uint256 d = _computeLiquidityFromAdjustedBalances(xpIn, xpOut);
        uint256 x = xpIn + amountIn;
        uint256 y = _getY(x, d);
        uint256 dy = xpOut - y - 1;
        //console.log("D, y", d, y);
        //console.log("out", dy);
        dy /= (token0In ? token1PrecisionMultiplier : token0PrecisionMultiplier);
        return dy;
    }

    /**
     * @notice Calculate the new balances of the tokens given the indexes of the token
     * that is swapped from (FROM) and the token that is swapped to (TO).
     * This function is used as a helper function to calculate how much TO token
     * the user should receive on swap.
     *
     * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L432
     *
     * @param x the new total amount of FROM token
     * @return the amount of TO token that should remain in the pool
     */
    function _getY(uint256 x, uint256 D) private view returns (uint256) {
        uint256 c = (D * D) / (x * 2);
        c = (c * D) / ((N_A * 2) / A_PRECISION);
        uint256 b = x + ((D * A_PRECISION) / N_A);
        uint256 yPrev;
        uint256 y = D;

        // iterative approximation
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = (y * y + c) / (y * 2 + b - D);
            if (y.within1(yPrev)) {
                break;
            }
        }
        return y;
    }

    /**
     * @notice Calculate the price of a token in the pool given
     * precision-adjusted balances and a particular D and precision-adjusted
     * array of balances.
     *
     * @dev This is accomplished via solving the quadratic equation iteratively.
     * See the StableSwap paper and Curve.fi implementation for further details.
     *
     * x_1**2 + x1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
     * x_1**2 + b*x_1 = c
     * x_1 = (x_1**2 + c) / (2*x_1 + b)
     *
     * @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L276
     *
     * @return the price of the token, in the same precision as in xp
     */
    function _getYD(
        uint256 s, //xpOut
        uint256 d
    ) internal view returns (uint256) {
        uint256 c = (d * d) / (s * 2);
        c = (c * d) / ((N_A * 2) / A_PRECISION);

        uint256 b = s + ((d * A_PRECISION) / N_A);
        uint256 yPrev;
        uint256 y = d;
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = (y * y + c) / (y * 2 + b - d);
            if (y.within1(yPrev)) {
                break;
            }
        }
        return y;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../deployer/MasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "../libraries/RebaseLibrary.sol";
import "../libraries/concentratedPool/TickMath.sol";
import "../libraries/concentratedPool/FullMath.sol";
import "../libraries/concentratedPool/UnsafeMath.sol";
import "../libraries/concentratedPool/DyDxMath.sol";
import "./TridentNFT.sol";
import "hardhat/console.sol";

/// @notice Trident exchange pool template with concentrated liquidity and constant product formula for swapping between an ERC-20 token pair.
/// @dev The reserves are stored as bento shares. However, the constant product curve is applied to the underlying amounts.
///      The API uses the underlying amounts.
abstract contract Cpcp is TridentNFT {
    using RebaseLibrary for Rebase;
    
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Sync(uint256 reserveShares0, uint256 reserveShares4);
    
    event Swap(
        address indexed recipient,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
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
    
    uint112 public liquidity;
    uint160 public sqrtPriceX96;
    int24 public nearestTick; // @dev Tick that is just below the current price.
    
    mapping(int24 => Tick) public ticks;
    struct Tick {
        int24 previousTick;
        int24 nextTick;
        uint112 liquidity;
    }

    bytes32 public constant poolIdentifier = "Trident:ConcentratedLiquidity";
    
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
        (address tokenA, address tokenB, uint256 _swapFee, uint160 _sqrtPriceX96) = abi.decode(
            _deployData,
            (address, address, uint256, uint160)
        );

        require(tokenA != address(0), "ConcentratedLiquidityPool: ZERO_ADDRESS");
        require(tokenA != tokenB, "ConcentratedLiquidityPool: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "ConcentratedLiquidityPool: INVALID_SWAP_FEE");

        token0 = tokenA;
        token1 = tokenB;
        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        sqrtPriceX96 = _sqrtPriceX96;
        ticks[TickMath.MIN_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint112(0));
        ticks[TickMath.MAX_TICK] = Tick(TickMath.MIN_TICK, TickMath.MAX_TICK, uint112(0));
        nearestTick = TickMath.MIN_TICK;
        bento = IBentoBoxMinimal(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
    }
    
    function mint(bytes calldata data) public lock {
        (int24 lowerOld, int24 lower, int24 upperOld, int24 upper, uint112 amount, address recipient) = abi.decode(
            data,
            (int24, int24, int24, int24, uint112, address)
        );
    
        uint160 priceLower = TickMath.getSqrtRatioAtTick(lower);
        uint160 priceUpper = TickMath.getSqrtRatioAtTick(upper);
        uint160 currentPrice = sqrtPriceX96;

        if (priceLower < currentPrice && currentPrice < priceUpper) liquidity += amount;

        updateLinkedList(lowerOld, lower, upperOld, upper, amount);
        updateNearestTickPointer(lower, upper, nearestTick, currentPrice);

        (uint256 amount0, uint256 amount1) = getAssets(uint256(priceLower), uint256(priceUpper), uint256(currentPrice), uint256(amount));
        
        _mint(lower, upper, amount, recipient);
        
        emit Mint(msg.sender, amount0, amount1, recipient);
    }
  
    function getAssets(
        uint256 priceLower,
        uint256 priceUpper,
        uint256 _sqrtPriceX96,
        uint256 liquidityAmount
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        amount0;
        amount1;

        if (priceUpper < _sqrtPriceX96) {
            // think about edgecases here <= vs <
            // only supply token1 (token1 is Y)
            amount1 = DyDxMath.getDy(liquidityAmount, priceLower, priceUpper, true);
        } else if (_sqrtPriceX96 < priceLower) {
            // only supply token0 (token0 is X)
            amount0 = DyDxMath.getDx(liquidityAmount, priceLower, priceUpper, true);
        } else {
            // supply both tokens
            amount0 = DyDxMath.getDx(liquidityAmount, _sqrtPriceX96, priceUpper, true);
            amount1 = DyDxMath.getDy(liquidityAmount, priceLower, _sqrtPriceX96, true);
        }
    }

    function updateNearestTickPointer(
        int24 lower,
        int24 upper,
        int24 currentNearestTick,
        uint160 _sqrtPriceX96
    ) internal {
        int24 actualNearestTick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);

        if (currentNearestTick < lower && lower <= actualNearestTick) currentNearestTick = lower;
        if (currentNearestTick < upper && upper <= actualNearestTick) currentNearestTick = upper;

        nearestTick = currentNearestTick;
    }

    function updateLinkedList(
        int24 lowerOld,
        int24 lower,
        int24 upperOld,
        int24 upper,
        uint112 amount
    ) internal {
        require(uint24(lower) % 2 == 0, "Lower even");
        require(uint24(upper) % 2 == 1, "Upper odd");

        require(lower < upper, "Order");

        require(TickMath.MIN_TICK <= lower && lower < TickMath.MAX_TICK, "Lower range");
        require(TickMath.MIN_TICK < upper && upper <= TickMath.MAX_TICK, "Upper range");

        if (ticks[lower].liquidity > 0 || lower == TickMath.MIN_TICK) {
            // we are adding liquidity to an existing tick
            ticks[lower].liquidity += amount;
        } else {
            // inserting a new tick
            Tick storage old = ticks[lowerOld];

            require(
                (old.liquidity > 0 || lowerOld == TickMath.MIN_TICK) && lowerOld < lower && lower < old.nextTick,
                "Lower order"
            );

            ticks[lower] = Tick(lowerOld, old.nextTick, amount);
            old.nextTick = lower;
        }

        if (ticks[upper].liquidity > 0 || upper == TickMath.MAX_TICK) {
            // we are adding liquidity to an existing tick
            ticks[upper].liquidity += amount;
        } else {
            // inserting a new tick
            Tick storage old = ticks[upperOld];

            require(old.liquidity > 0 && old.nextTick > upper && upperOld < upper, "Upper order");

            ticks[upper] = Tick(upperOld, old.nextTick, amount);
            old.nextTick = upper;
        }
    }

    // price is √(y/x)
    // x is token0
    // zero for one -> price will move down
    function swap(
        bool zeroForOne,
        uint256 amount,
        address recipient,
        bool unwrapBento
    ) public {
        int24 nextTickToCross = zeroForOne ? nearestTick : ticks[nearestTick].nextTick;
        uint256 currentPrice = uint256(sqrtPriceX96);
        uint256 currentLiquidity = uint256(liquidity);
        uint256 outAmount;
        uint256 inAmount = amount;

        while (amount > 0) {
            uint256 nextTickPrice = uint256(TickMath.getSqrtRatioAtTick(nextTickToCross));

            if (zeroForOne) {
                // x for y
                // price is going down
                // max swap input within current tick range: Δx = Δ(1/√𝑃) · L
                uint256 maxDx = DyDxMath.getDx(currentLiquidity, nextTickPrice, currentPrice, false);
                if (amount <= maxDx) {
                    // we can swap only within the current range
                    uint256 liquidityPadded = currentLiquidity << 96;
                    // calculate new price after swap: L · √𝑃 / (L + Δx · √𝑃)
                    // alternatively: L / (L / √𝑃 + Δx)
                    uint256 newPrice = uint160(
                        FullMath.mulDivRoundingUp(
                            liquidityPadded,
                            currentPrice,
                            liquidityPadded + currentPrice * amount
                        )
                    );

                    if (!(nextTickPrice <= newPrice && newPrice < currentPrice)) {
                        // owerflow -> use a modified version of the formula
                        newPrice = uint160(
                            UnsafeMath.divRoundingUp(liquidityPadded, liquidityPadded / currentPrice + amount)
                        );
                    }

                    // calculate output of swap
                    // Δy = Δ√P · L
                    outAmount += DyDxMath.getDy(currentLiquidity, newPrice, currentPrice, false);
                    amount = 0;
                    currentPrice = newPrice;
                } else {
                    // swap & cross the tick
                    amount -= maxDx;
                    outAmount += DyDxMath.getDy(currentLiquidity, nextTickPrice, currentPrice, false);

                    if (nextTickToCross % 2 == 0) {
                        currentLiquidity = currentLiquidity - uint256(ticks[nextTickToCross].liquidity);
                    } else {
                        currentLiquidity = currentLiquidity + uint256(ticks[nextTickToCross].liquidity);
                    }

                    currentPrice = nextTickPrice;
                    nextTickToCross = ticks[nextTickToCross].previousTick;
                }
            } else {
                // price is going up
                // max swap within current tick range: Δy = Δ√P · L
                uint256 maxDy = DyDxMath.getDy(currentLiquidity, currentPrice, nextTickPrice, false);

                if (amount <= maxDy) {
                    // we can swap only within the current range
                    // calculate new price after swap ( ΔP = Δy/L )
                    uint256 newPrice;

                    if (amount <= type(uint160).max) {
                        newPrice = currentPrice + (amount << 96) / currentLiquidity;
                    } else {
                        newPrice =
                            currentPrice +
                            uint160(FullMath.mulDiv(amount, 0x1000000000000000000000000, liquidity));
                    }

                    // calculate output of swap
                    // Δx = Δ(1/√P) · L
                    outAmount += DyDxMath.getDx(currentLiquidity, currentPrice, newPrice, false);
                    amount = 0;
                    currentPrice = newPrice;
                } else {
                    // swap & cross the tick
                    amount -= maxDy;
                    outAmount += DyDxMath.getDx(currentLiquidity, currentPrice, nextTickPrice, false);

                    if (nextTickToCross % 2 == 0) {
                        currentLiquidity = currentLiquidity + uint256(ticks[nextTickToCross].liquidity);
                    } else {
                        currentLiquidity = currentLiquidity - uint256(ticks[nextTickToCross].liquidity);
                    }

                    currentPrice = nextTickPrice;
                    nextTickToCross = ticks[nextTickToCross].nextTick;
                }
            }
        }

        liquidity = uint112(currentLiquidity);
        sqrtPriceX96 = uint160(currentPrice);
        nearestTick = zeroForOne ? nextTickToCross : ticks[nextTickToCross].previousTick;

        if (zeroForOne) {
            _transferShares(token1, outAmount, recipient, unwrapBento);
            emit Swap(recipient, token0, token1, inAmount, outAmount);
        } else {
            _transferShares(token0, outAmount, recipient, unwrapBento);
            emit Swap(recipient, token1, token0, inAmount, outAmount);
        }
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
    
    function _balance(Rebases memory _rebase) internal view returns (Holdings memory _balances) {
        _balances.shares0 = bento.balanceOf(token0, address(this));
        _balances.shares1 = bento.balanceOf(token1, address(this));
        _balances.amount0 = _rebase.total0.toElastic(_balances.shares0);
        _balances.amount1 = _rebase.total1.toElastic(_balances.shares1);
    }
}

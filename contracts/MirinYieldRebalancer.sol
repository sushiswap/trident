// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./interfaces/IMasterChefV2.sol";
import "./interfaces/IMirinTwapOracle.sol";
import "./interfaces/IMirinPool.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/MirinLibrary.sol";
import "./ERC20.sol";

contract MirinYieldRebalancer is ERC20("SushiRebalancer", "rSUSHI") {
    using SafeERC20 for IERC20;

    IMasterChefV2 public immutable masterChef;
    IERC20 public immutable sushi;
    IMirinTwapOracle public immutable oracle;
    address public immutable factory;
    address public immutable legacyFactory;
    address public immutable weth;

    mapping(uint256 => uint256) public shares;
    uint256 public totalShares;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "MIRIN: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event Mint(address indexed from, address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event Deposit(uint256 indexed pid, uint256 liquidity);
    event Withdraw(uint256 indexed pid, uint256 liquidity);

    constructor(
        IMasterChefV2 _masterChef,
        IERC20 _sushi,
        IMirinTwapOracle _oracle,
        address _factory,
        address _legacyFactory,
        address _weth
    ) {
        masterChef = _masterChef;
        sushi = _sushi;
        oracle = _oracle;
        factory = _factory;
        legacyFactory = _legacyFactory;
        weth = _weth;
    }

    function getPoolAndToken(uint256 pid) public view returns (IMirinPool pool, address token) {
        pool = IMirinPool(masterChef.lpToken(pid));
        (address token0, address token1) = (pool.token0(), pool.token1());
        require(token0 == weth || token1 == weth, "MIRIN: INVALID_POOL");
        token = token0 == weth ? token1 : token0;
    }

    function mint(
        uint256 pid,
        uint256 amountSushiIn,
        uint256 liquidityMin,
        address to
    ) external lock {
        require(amountSushiIn > 0, "MIRIN: INVALID_AMOUNT");

        sushi.transferFrom(msg.sender, address(this), amountSushiIn);
        _deposit(pid, amountSushiIn, liquidityMin);

        uint256 _totalSupply = totalSupply();
        _mint(
            to,
            (_totalSupply == 0 || totalShares == 0) ? amountSushiIn : (amountSushiIn * _totalSupply) / totalShares
        );

        shares[pid] += amountSushiIn;
        totalShares += amountSushiIn;

        emit Mint(msg.sender, to, amountSushiIn);
    }

    function _deposit(
        uint256 pid,
        uint256 amountSushiIn,
        uint256 liquidityMin
    ) private {
        (IMirinPool lpToken, address token) = getPoolAndToken(pid);
        // swap weth to sushi
        uint256 amountWETHOut = _swapTokens(amountSushiIn / 2, weth, address(sushi), address(lpToken));
        // swap token to sushi
        uint256 amountTokenOut = _swapTokens(amountSushiIn / 2, token, address(sushi), address(lpToken));

        // mint lp tokens
        uint256 liquidity = lpToken.mint(address(this));
        require(liquidity >= liquidityMin, "MIRIN: INSUFFICIENT_LIQUIDITY");

        // deposit lp tokens
        lpToken.approve(address(masterChef), liquidity);
        masterChef.deposit(pid, liquidity, address(this));

        emit Deposit(pid, liquidity);
    }

    function burn(
        uint256 pid,
        uint256 liquidityOut,
        uint256 amountSushiOutMin,
        address to
    ) external lock {
        uint256 amountOut = _withdraw(pid, liquidityOut);
        require(amountOut >= amountSushiOutMin, "MIRIN: INSUFFICIENT_SUSHI");

        uint256 poolShare = shares[pid];
        uint256 lpTotal = masterChef.userInfo(pid, address(this)).amount;
        uint256 share = (liquidityOut * poolShare) / lpTotal;

        // burn rSUSHI
        uint256 _totalShares = totalShares;
        uint256 poolSupply = (poolShare * totalSupply()) / _totalShares;
        _burn(msg.sender, (liquidityOut * poolSupply) / lpTotal);
        // transfer reward
        sushi.transfer(to, (share * sushi.balanceOf(address(this))) / _totalShares);
        // update shares
        shares[pid] -= share;
        totalShares -= share;

        emit Burn(msg.sender, share);
    }

    function _withdraw(uint256 pid, uint256 liquidityOut) private returns (uint256 amountOut) {
        // withdraw from MasterChef
        masterChef.withdrawAndHarvest(pid, liquidityOut, address(this));

        // burn lp tokens
        (IMirinPool lpToken, address token) = getPoolAndToken(pid);
        lpToken.transfer(address(lpToken), lpToken.balanceOf(address(this)));
        lpToken.burn(address(this));

        // swap token to sushi
        amountOut += _swapTokens(IERC20(token).balanceOf(address(this)), token, address(sushi), address(this));
        // swap weth to sushi
        amountOut += _swapTokens(IERC20(weth).balanceOf(address(this)), weth, address(sushi), address(this));

        emit Withdraw(pid, liquidityOut);
    }

    function _swapTokens(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        address to
    ) private returns (uint256 amountOut) {
        if (tokenIn == tokenOut) {
            IERC20(tokenIn).safeTransfer(to, amountIn);
            return amountIn;
        }

        address pool = MirinLibrary.getPool(factory, legacyFactory, tokenIn, tokenOut, 0);
        IERC20(tokenOut).safeTransfer(pool, amountIn);

        (uint112 reserve0, uint112 reserve1, ) = IMirinPool(pool).getReserves();
        address token0 = IMirinPool(pool).token0();
        amountOut = IMirinCurve(IMirinPool(pool).curve()).computeAmountOut(
            amountIn,
            reserve0,
            reserve1,
            IMirinPool(pool).curveData(),
            IMirinPool(pool).swapFee(),
            token0 == tokenIn ? 0 : 1
        );
        (uint256 amount0Out, uint256 amount1Out) =
            token0 == tokenIn ? (uint256(0), amountOut) : (amountOut, uint256(0));
        IMirinPool(pool).swap(amount0Out, amount1Out, to, bytes(""));
    }

    function rebalance(
        uint256 pidFrom,
        uint256 amountFrom,
        uint256 pidTo,
        uint256 amountToMin
    ) external {
        // TODO
    }
}

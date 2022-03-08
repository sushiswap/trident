pragma solidity ^0.8.2;

import "../../contracts/pool/hybrid/HybridPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HybridPoolHarness is HybridPool {
    // state variables ///////////
    uint256 public MAX_FEE_MINUS_SWAP_FEE;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => mapping(bool => uint256)))) public amountOutHarness;
    address public otherHarness;
    address public tokenInHarness;

    // constructor ///////////////
    constructor(bytes memory _deployData, address _masterDeployer) HybridPool(_deployData, _masterDeployer) {
        (address tokenA, address tokenB, uint256 _swapFee, bool _twapSupport) = abi.decode(_deployData, (address, address, uint256, bool));

        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee; // TODO: check this with Nurit
    }

    // getters ///////////////////
    function tokenBalanceOf(IERC20 token, address user) public view returns (uint256 balance) {
        return token.balanceOf(user);
    }

    // wrappers //////////////////
    function mintWrapper(address to) public returns (uint256 liquidity) {
        bytes memory data = abi.encode(to);

        return super.mint(data);
    }

    function burnWrapper(address to, bool unwrapBento) public returns (uint256 liquidity0_, uint256 liquidity1_) {
        bytes memory data = abi.encode(to, unwrapBento);

        IPool.TokenAmount[] memory withdrawnAmounts = super.burn(data);

        return (withdrawnAmounts[0].amount, withdrawnAmounts[1].amount);
    }

    function burnSingleWrapper(
        address tokenOut,
        address to,
        bool unwrapBento
    ) public returns (uint256 amount) {
        bytes memory data = abi.encode(tokenOut, to, unwrapBento);

        return super.burnSingle(data);
    }

    // swapWrapper
    function swapWrapper(
        address tokenIn,
        address recipient,
        bool unwrapBento
    ) public returns (uint256 amountOut) {
        bytes memory data = abi.encode(tokenIn, recipient, unwrapBento);

        return super.swap(data);
    }

    function flashSwapWrapper(
        address tokenIn,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        bytes memory context
    ) public returns (uint256 amountOut) {
        require(otherHarness != recipient, "recepient is other");
        require(tokenInHarness == tokenIn);

        bytes memory data = abi.encode(tokenIn, recipient, unwrapBento, amountIn, context);

        return super.flashSwap(data);
    }

    function getAmountOutWrapper(address tokenIn, uint256 amountIn) public view returns (uint256 finalAmountOut) {
        bytes memory data = abi.encode(tokenIn, amountIn);

        return super.getAmountOut(data);
    }

    // overrides /////////////////
    // WARNING: Be careful of interlocking "lock" modifier
    // if adding to the overrided code blocks
    function mint(bytes memory data) public override  nonReentrant returns (uint256 liquidity) {}

    function burn(bytes memory data) public override  nonReentrant returns (IPool.TokenAmount[] memory withdrawnAmounts) {}

    function burnSingle(bytes memory data) public override  nonReentrant returns (uint256 amount) {}

    function swap(bytes memory data) public override  nonReentrant returns (uint256 amountOut) {}

    function flashSwap(bytes memory data) public override  nonReentrant returns (uint256 amountOut) {}

    function getAmountOut(bytes memory data) public view override returns (uint256 finalAmountOut) {}

    // simplifications ///////////
    // TODO: would need to do it for HybridPool
    // function _getAmountOut(
    //     uint256 amountIn,
    //     uint256 reserveIn,
    //     uint256 reserveOut
    // ) internal view override returns (uint256) {
    //     if (amountIn == 0 || reserveOut == 0) {
    //         return 0;
    //     }

    //     return amountOutHarness[amountIn][reserveIn][reserveOut];
    // }

    function _getAmountOut(
        uint256 amountIn,
        uint256 _reserve0,
        uint256 _reserve1,
        bool token0In
    ) public view override returns (uint256) {
        // TODO: add assumptions as per the properties of _getAmountOut
        return amountOutHarness[amountIn][_reserve0][_reserve1][token0In];
    }
}

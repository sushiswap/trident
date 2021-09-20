/* 
    This is a symbolic pool used for verification with Certora Prover.
    Variables are symbolic so no need to initialize them, the Prover will
    simulate all possible values.
*/

pragma solidity ^0.8.2;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/interfaces/IPool.sol";
import "../../contracts/interfaces/IBentoBoxMinimal.sol";
import "../../contracts/pool/TridentERC20.sol";

contract SymbolicPool is IPool, TridentERC20 {
    IBentoBoxMinimal public bento;

    // There is a set of tokens this pool supports
    address public token0;
    address public token1;
    uint256 internal constant NUM_TOKENS = 2;

    // the amount of holding the pool has for each token[i]
    mapping(address => uint256) public reserves;

    // a symbolic representation of fixed conversion ratio between each two tokens
    mapping(address => mapping(address => uint256)) public rates;

    // TODO: no fee, no lock?
    // TODO: unwrapBento not being used
    function swap(bytes calldata data) external override returns (uint256) {
        (address tokenIn, address recipient, bool unwrapBento) = abi.decode(data, (address, address, bool));

        // TODO: do we want to make this more generic?
        require(tokenIn == address(token0));
        address tokenOut = token1;

        uint256 amountIn = bento.balanceOf(tokenIn, address(this)) - reserves[tokenIn];

        return basicSwap(tokenIn, tokenOut, recipient, amountIn);
    }

    // TODO: flashSwap not calling any callback, do we want?
    // TODO: unwrapBento not being used
    function flashSwap(bytes calldata data) external override returns (uint256 amountOut) {
        (address tokenIn, address recipient, bool unwrapBento, uint256 amountIn, bytes memory context) = abi.decode(
            data,
            (address, address, bool, uint256, bytes)
        );

        // TODO: do we want to make this more generic?
        require(tokenIn == address(token0));
        address tokenOut = token1;

        amountOut = basicSwap(tokenIn, tokenOut, recipient, amountIn);

        require(bento.balanceOf(tokenIn, address(this)) - reserves[tokenIn] >= amountIn, "INSUFFICIENT_AMOUNT_IN");
    }

    function basicSwap(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn
    ) internal returns (uint256 finalAmountOut) {
        // a symbolic value representing the computed amountOut which is a
        // function of the current reserve state and amountIn
        finalAmountOut = rates[tokenIn][tokenOut] * amountIn;

        // assumption - finalAmoutOut is not zero for non zero amountIn
        require(rates[tokenIn][tokenOut] != 0);

        // transfer to  recipient
        bento.transfer(tokenOut, address(this), recipient, finalAmountOut);

        update(tokenIn);
        update(tokenOut);
    }

    // a basic one to one mapping
    function mint(bytes memory data) external override returns (uint256 liquidity) {
        address to = abi.decode(data, (address));

        // just a simple relationship
        // the number of pool tokens a user will get is the sum of tokens they deposit.
        liquidity = bento.balanceOf(address(token0), address(this)) - reserves[address(token0)];
        liquidity += bento.balanceOf(address(token1), address(this)) - reserves[address(token1)];

        _mint(to, liquidity);

        update(token0);
        update(token1);
    }

    // returns amount of shares in bentobox
    // TODO: not using unwrapBento
    // TODO: return value
    function burn(bytes memory data) external override returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (address to, bool unwrapBento) = abi.decode(data, (address, bool));

        // how much liquidity passed to the pool for burning
        uint256 liquidity = balanceOf[address(this)];

        _burn(address(this), liquidity);

        uint256 split = getSplitValue(liquidity);

        withdrawnAmounts = new TokenAmount[](2);

        bento.transfer(token0, address(this), to, split);
        withdrawnAmounts[0] = TokenAmount({token: address(token0), amount: split});

        bento.transfer(token1, address(this), to, split);
        withdrawnAmounts[1] = TokenAmount({token: address(token1), amount: split});

        update(token0);
        update(token1);
    }

    // TODO: unwrapBento not being used
    function burnSingle(bytes memory data) external override returns (uint256 amount) {
        (address tokenOut, address to, bool unwrapBento) = abi.decode(data, (address, address, bool));

        uint256 amount = balanceOf[address(this)];

        _burn(address(this), amount);

        bento.transfer(address(tokenOut), address(this), to, amount);

        update(address(tokenOut));
    }

    function update(address token) internal {
        reserves[token] = bento.balanceOf(token, address(this));
    }

    function getSplitValue(uint256 liquidity) private pure returns (uint256) {
        return liquidity / 2;
    }

    function getAmountOut(bytes calldata data) external view override returns (uint256 finalAmountOut) {}

    function getAssets() external view override returns (address[] memory) {}

    function poolIdentifier() external pure override returns (bytes32) {
        return "";
    }

    function reserve0() external view returns (uint256) {
        return reserves[token0];
    }

    function reserve1() external view returns (uint256) {
        return reserves[token1];
    }
}

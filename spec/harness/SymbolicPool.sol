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
import "../../contracts/interfaces/ITridentCallee.sol";

contract SymbolicPool is IPool, TridentERC20 {
    IBentoBoxMinimal public bento;
    // The set of tokens this pool supports
    address public token0;
    address public token1;
    uint256 internal constant NUM_TOKENS = 2;
    // the amount of holding the pool has for each token[i]
    mapping(address => uint256) public reserves;
    // a symbolic representation of fixed conversion ratio between each two tokens
    mapping(address => mapping(address => uint256)) public rates;

    // main public functions ///////////////
    function mint(bytes memory data) external override returns (uint256 liquidity) {
        address to = abi.decode(data, (address));

        // a simple relationship: the number of pool tokens
        // a user will get is the sum of tokens they deposit.
        liquidity = bento.balanceOf(token0, address(this)) - reserves[token0];
        liquidity += bento.balanceOf(token1, address(this)) - reserves[token1];

        _mint(to, liquidity);

        update(token0);
        update(token1);
    }

    // returns amount of shares in bentobox
    // TODO: return value not in the spec
    function burn(bytes memory data) external override returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (address to, bool unwrapBento) = abi.decode(data, (address, bool));

        // how much liquidity is passed to the pool for burning
        uint256 liquidity = balanceOf[address(this)];

        _burn(address(this), liquidity);

        // TODO: since we are not using getAmountOut, burning 2 SymbolicPool
        // tokens returns 1 token0 and 1 token1
        uint256 split = getSplitValue(liquidity);

        withdrawnAmounts = new TokenAmount[](2);

        _transfer(token0, split, to, unwrapBento);
        withdrawnAmounts[0] = TokenAmount({token: token0, amount: split});

        _transfer(token1, split, to, unwrapBento);
        withdrawnAmounts[1] = TokenAmount({token: token1, amount: split});

        update(token0);
        update(token1);
    }

    function burnSingle(bytes memory data) external override returns (uint256 amountOut) {
        (address tokenOut, address to, bool unwrapBento) = abi.decode(data, (address, address, bool));

        uint256 liquidity = balanceOf[address(this)];
        // TODO: since we are not using getAmountOut, burning n SymbolicPool
        // tokens returns n tokenOut tokens
        amountOut = liquidity;

        _burn(address(this), liquidity);

        _transfer(tokenOut, amountOut, to, unwrapBento);

        update(tokenOut);
    }

    function swap(bytes calldata data) external override returns (uint256) {
        (address tokenIn, address recipient, bool unwrapBento) = abi.decode(data, (address, address, bool));

        address tokenOut;

        if (tokenIn == token0) {
            tokenOut = token1;
        } else {
            // TODO: this is needed, check with Nurit
            require(tokenIn == token1);
            tokenOut = token0;
        }

        uint256 amountIn = bento.balanceOf(tokenIn, address(this)) - reserves[tokenIn];

        return basicSwap(tokenIn, tokenOut, recipient, amountIn, unwrapBento);
    }

    function flashSwap(bytes calldata data) external override returns (uint256 amountOut) {
        (address tokenIn, address recipient, bool unwrapBento, uint256 amountIn, bytes memory context) = abi.decode(
            data,
            (address, address, bool, uint256, bytes)
        );

        address tokenOut;

        if (tokenIn == token0) {
            tokenOut = token1;
        } else {
            // TODO: this is needed, check with Nurit
            require(tokenIn == token1);
            tokenOut = token0;
        }

        amountOut = basicSwap(tokenIn, tokenOut, recipient, amountIn, unwrapBento);

        // TODO: this is needed, check with Nurit
        ITridentCallee(msg.sender).tridentSwapCallback(context);

        require(bento.balanceOf(tokenIn, address(this)) - reserves[tokenIn] >= amountIn, "INSUFFICIENT_AMOUNT_IN");
    }

    // Setters & Getters ///////////////////
    function update(address token) internal {
        reserves[token] = bento.balanceOf(token, address(this));
    }

    function reserve0() external view returns (uint256) {
        return reserves[token0];
    }

    function reserve1() external view returns (uint256) {
        return reserves[token1];
    }

    // Override Simplifications ////////////
    function getAmountOut(bytes calldata data) external view override returns (uint256 finalAmountOut) {}

    function getAssets() external view override returns (address[] memory) {}

    function poolIdentifier() external pure override returns (bytes32) {
        return "";
    }

    // Helper Functions ////////////////////
    function basicSwap(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        bool unwrapBento
    ) internal returns (uint256 finalAmountOut) {
        // a symbolic value representing the computed amountOut which is a
        // function of the current reserve state and amountIn
        finalAmountOut = rates[tokenIn][tokenOut] * amountIn;

        // assumption - finalAmoutOut is not zero for non zero amountIn
        require(rates[tokenIn][tokenOut] != 0);

        // transfer to recipient
        _transfer(tokenOut, finalAmountOut, recipient, unwrapBento);

        update(tokenIn);
        update(tokenOut);
    }

    function _transfer(
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

    function getSplitValue(uint256 liquidity) private pure returns (uint256) {
        return liquidity / 2;
    }

    //not used by contract
    function getAmountIn(bytes calldata data) external view override returns (uint256 finalAmountIn) {

     }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../deployer/MasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "./TridentERC20.sol";
import "hardhat/console.sol";

/// @notice Trident exchange pool template with constant mean formula for swapping between an array of ERC-20 tokens.
/// @dev The reserves are stored as bento shares.
///      The curve is applied to shares as well. This pool does not care about the underlying amounts.
contract IndexPool is IPool, TridentERC20 {
    event Mint(address indexed sender, address tokenIn, uint256 amountIn, address indexed recipient);
    event Burn(address indexed sender, address tokenOut, uint256 amountOut, address indexed recipient);

    uint256 internal constant MAX_FEE = 10000; // @dev 100%.
    uint256 internal constant MAX_FEE_SQUARE = 100000000;
    uint256 public immutable swapFee;
    uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE;

    address internal immutable barFeeTo;
    IBentoBoxMinimal public immutable bento;
    MasterDeployer public immutable masterDeployer;

    bytes32 public constant override poolIdentifier = "Trident:Index";

    uint256 internal constant BASE = 10**18;
    uint256 internal constant MIN_BOUND_TOKENS = 2;
    uint256 internal constant MAX_BOUND_TOKENS = 8;
    uint256 internal constant MIN_WEIGHT = BASE;
    uint256 internal constant MAX_WEIGHT = BASE * 50;
    uint256 internal constant MAX_TOTAL_WEIGHT = BASE * 50;
    uint256 internal constant MIN_BALANCE = BASE / 10**12;
    uint256 internal constant INIT_POOL_SUPPLY = BASE * 100;
    uint256 internal constant MAX_IN_RATIO = BASE / 2;
    uint256 internal constant MAX_OUT_RATIO = (BASE / 3) + 1 wei;

    address[] private tokens;
    uint256 public totalWeight;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    mapping(address => Record) public records;
    struct Record {
        bool bound;
        uint8 index;
        uint256 weight;
        uint256 amount;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address[] memory _tokens, uint256[] memory _weights, uint256 _swapFee) = abi.decode(
            _deployData,
            (address[], uint256[], uint256)
        );

        require(_tokens.length == _weights.length, "ARRAY_MISMATCH");
        require(_swapFee <= MAX_FEE, "INVALID_SWAP_FEE");

        for (uint8 i = 0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), "ZERO_ADDRESS");
            require(!records[_tokens[i]].bound, "BOUND");
            require(_weights[i] >= MIN_WEIGHT, "MIN_WEIGHT");
            require(_weights[i] <= MAX_WEIGHT, "MAX_WEIGHT");
            require(_tokens.length >= MIN_BOUND_TOKENS, "MIN_TOKENS");
            require(_tokens.length <= MAX_BOUND_TOKENS, "MAX_TOKENS");
            totalWeight += _weights[i];
            require(totalWeight <= MAX_TOTAL_WEIGHT, "MAX_TOTAL_WEIGHT");

            records[_tokens[i]] = Record({bound: true, index: i, weight: _weights[i], amount: 0});

            tokens.push(_tokens[i]);
        }

        _mint(address(0), INIT_POOL_SUPPLY); // @dev This burns initial LP supply.

        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxMinimal(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
    }

    function mint(bytes calldata data) public override lock returns (uint256 liquidity) {
        (uint256 toMint, address recipient) = abi.decode(data, (uint256, address));

        uint256 ratio = toMint / totalSupply;

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenIn = tokens[i];
            uint256 amount = records[tokenIn].amount;
            // @dev If token amount is 0, initialize with `ratio`.
            uint256 amountIn = amount != 0 ? ratio * amount : ratio;
            require(amountIn >= MIN_BALANCE, "MIN_BALANCE");
            // @dev Check Trident router has sent amount for skim into pool.
            require(_balance(tokenIn) >= amountIn + amount, "NOT_RECEIVED");
            records[tokenIn].amount += amountIn;
            emit Mint(msg.sender, tokenIn, amountIn, recipient);
        }

        _mint(recipient, toMint);

        liquidity = toMint;
    }

    function burn(bytes calldata data) public override lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (uint256 toBurn, address recipient, bool unwrapBento) = abi.decode(data, (uint256, address, bool));

        uint256 ratio = toBurn / totalSupply;

        _burn(address(this), toBurn);

        withdrawnAmounts = new TokenAmount[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenOut = tokens[i];
            uint256 amount = records[tokenOut].amount;
            uint256 amountOut = ratio * amount;
            require(amountOut != 0, "MATH_APPROX");
            records[tokenOut].amount = amount - amountOut;
            _transfer(tokenOut, amountOut, recipient, unwrapBento);
            withdrawnAmounts[i] = TokenAmount({token: tokenOut, amount: amountOut});
            emit Burn(msg.sender, tokenOut, amountOut, recipient);
        }
    }

    function burnSingle(bytes calldata data) public override lock returns (uint256 amount) {
        (address tokenOut, uint256 toBurn, address recipient, bool unwrapBento) = abi.decode(
            data,
            (address, uint256, address, bool)
        );

        Record storage outRecord = records[tokenOut];

        require(outRecord.bound, "ERR_NOT_BOUND");

        amount = calcSingleOutGivenPoolIn(
            outRecord.amount,
            outRecord.weight,
            totalSupply,
            totalWeight,
            toBurn,
            swapFee
        );

        require(amount <= outRecord.amount * MAX_OUT_RATIO, "ERR_MAX_OUT_RATIO");

        outRecord.amount = outRecord.amount - amount;

        _burn(address(this), toBurn);
        _transfer(tokenOut, amount, recipient, unwrapBento);

        emit Burn(msg.sender, tokenOut, amount, recipient);
    }

    function swap(bytes calldata data) public override returns (uint256 amountOut) {
        require(unlocked == 1, "LOCKED");
        (address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountIn) = abi.decode(
            data,
            (address, address, address, bool, uint256)
        );

        require(records[tokenIn].bound, "NOT_BOUND");
        require(records[tokenOut].bound, "NOT_BOUND");

        Record storage inRecord = records[tokenIn];
        Record storage outRecord = records[tokenOut];

        require(amountIn <= inRecord.amount * MAX_IN_RATIO, "MAX_IN_RATIO");

        amountOut = _getAmountOut(inRecord.amount, inRecord.weight, outRecord.amount, outRecord.weight, amountIn);
        // @dev Check Trident router has sent amount for skim into pool.
        require(_balance(tokenIn) >= amountIn + inRecord.amount, "NOT_RECEIVED");

        inRecord.amount += amountIn;
        outRecord.amount -= amountOut;

        _transfer(tokenOut, amountOut, recipient, unwrapBento);

        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function flashSwap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (
            address tokenIn,
            address tokenOut,
            address recipient,
            bool unwrapBento,
            uint256 amountIn,
            bytes memory context
        ) = abi.decode(data, (address, address, address, bool, uint256, bytes));

        require(records[tokenIn].bound, "NOT_BOUND");
        require(records[tokenOut].bound, "NOT_BOUND");

        Record storage inRecord = records[tokenIn];
        Record storage outRecord = records[tokenOut];

        require(amountIn <= inRecord.amount * MAX_IN_RATIO, "MAX_IN_RATIO");

        amountOut = _getAmountOut(inRecord.amount, inRecord.weight, outRecord.amount, outRecord.weight, amountIn);

        ITridentCallee(recipient).tridentCallback(tokenIn, tokenOut, amountIn, amountOut, context);
        // @dev Check Trident router has sent amount for skim into pool.
        require(_balance(tokenIn) >= amountIn + inRecord.amount, "NOT_RECEIVED");

        inRecord.amount += amountIn;
        outRecord.amount -= amountOut;

        _transfer(tokenOut, amountOut, recipient, unwrapBento);

        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
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

    function _balance(address token) internal view returns (uint256 balance) {
        balance = bento.balanceOf(token, address(this));
    }

    function _getAmountOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountIn
    ) internal view returns (uint256 finalAmountOut) {
        uint256 weightRatio = tokenWeightIn / tokenWeightOut;
        uint256 adjustedIn = BASE - swapFee;
        adjustedIn = tokenAmountIn * adjustedIn;
        uint256 y = tokenBalanceIn / tokenBalanceIn + adjustedIn;
        uint256 foo = pow(y, weightRatio);
        uint256 bar = BASE - foo;
        finalAmountOut = tokenBalanceOut * bar;
    }

    function pow(uint256 a, uint256 n) internal pure returns (uint256) {
        uint256 z = n % 2 != 0 ? a : BASE;
        for (n /= 2; n != 0; n /= 2) {
            a = a * a;
            if (n % 2 != 0) {
                z = z * a;
            }
        }
        return z;
    }

    function calcSingleOutGivenPoolIn(
        uint256 amountOut,
        uint256 weightOut,
        uint256 _totalSupply,
        uint256 _totalWeight,
        uint256 toBurn,
        uint256 _swapFee
    ) internal pure returns (uint256 tokenAmountOut) {
        uint256 normalizedWeight = weightOut / _totalWeight;
        uint256 poolAmountInAfterExitFee = toBurn * (BASE - _swapFee);
        uint256 newPoolSupply = _totalSupply - poolAmountInAfterExitFee;
        uint256 poolRatio = newPoolSupply / _totalSupply;
        uint256 tokenOutRatio = pow(poolRatio, BASE / normalizedWeight);
        uint256 newAmountOut = tokenOutRatio * amountOut;
        uint256 tokenAmountOutBeforeSwapFee = amountOut - newAmountOut;
        uint256 zaz = (BASE - normalizedWeight) * _swapFee;
        tokenAmountOut = tokenAmountOutBeforeSwapFee * (BASE - zaz);
    }

    function getAmountOut(bytes calldata data) public view override returns (uint256 finalAmountOut) {
        (
            uint256 tokenBalanceIn,
            uint256 tokenWeightIn,
            uint256 tokenBalanceOut,
            uint256 tokenWeightOut,
            uint256 tokenAmountIn
        ) = abi.decode(data, (uint256, uint256, uint256, uint256, uint256));
        finalAmountOut = _getAmountOut(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn);
    }

    function getAssets() public view override returns (address[] memory assets) {
        assets = tokens;
    }

    function getNormalizedWeight(address asset) external view returns (uint256 norm) {
        norm = records[asset].weight / totalWeight;
    }

    function getDenormalizedWeight(address asset) external view returns (uint256 denorm) {
        denorm = records[asset].weight;
    }
}

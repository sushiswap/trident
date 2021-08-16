// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

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

    uint256 public immutable swapFee;

    address public immutable barFeeTo;
    address public immutable bento;
    address public immutable masterDeployer;

    bytes32 public constant override poolIdentifier = "Trident:Index";

    uint256 internal constant BASE = 10**18;
    uint256 internal constant MIN_TOKENS = 2;
    uint256 internal constant MAX_TOKENS = 8;
    uint256 internal constant MIN_FEE = BASE / 10**6;
    uint256 internal constant MAX_FEE = BASE / 10;
    uint256 internal constant MIN_WEIGHT = BASE;
    uint256 internal constant MAX_WEIGHT = BASE * 50;
    uint256 internal constant MAX_TOTAL_WEIGHT = BASE * 50;
    uint256 internal constant MIN_BALANCE = BASE / 10**12;
    uint256 internal constant INIT_POOL_SUPPLY = BASE * 100;
    uint256 internal constant MIN_POW_BASE = 1;
    uint256 internal constant MAX_POW_BASE = (2 * BASE) - 1;
    uint256 internal constant POW_PRECISION = BASE / 10**10;
    uint256 internal constant MAX_IN_RATIO = BASE / 2;
    uint256 internal constant MAX_OUT_RATIO = (BASE / 3) + 1;

    address[] internal tokens;
    uint256 internal totalWeight;

    uint256 internal unlocked;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    mapping(address => Record) public records;
    struct Record {
        bool set;
        uint8 index;
        uint256 weight;
        uint256 balance;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address[] memory _tokens, uint256[] memory _weights, uint256 _swapFee) = abi.decode(
            _deployData,
            (address[], uint256[], uint256)
        );

        require(_tokens.length == _weights.length, "INVALID_ARRAYS");
        require(MIN_FEE <= _swapFee && _swapFee <= MAX_FEE, "INVALID_SWAP_FEE");
        require(MIN_TOKENS <= _tokens.length && _tokens.length <= MAX_TOKENS, "INVALID_TOKENS_LENGTH");

        for (uint8 i = 0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), "ZERO_ADDRESS");
            require(!records[_tokens[i]].set, "SET");
            require(MIN_WEIGHT <= _weights[i] && _weights[i] <= MAX_WEIGHT, "INVALID_WEIGHT");
            records[_tokens[i]] = Record({set: true, index: i, weight: _weights[i], balance: 0});
            tokens.push(_tokens[i]);
            totalWeight += _weights[i];
        }
        
        require(totalWeight <= MAX_TOTAL_WEIGHT, "MAX_TOTAL_WEIGHT");
        // @dev This burns initial LP supply.
        _mint(address(0), INIT_POOL_SUPPLY); 

        (, bytes memory _bento) = _masterDeployer.staticcall(abi.encodeWithSelector(0x4da31827)); // @dev bento().
        (, bytes memory _barFeeTo) = _masterDeployer.staticcall(abi.encodeWithSelector(0x0c0a0cd2)); // @dev barFeeTo().
        
        bento = abi.decode(_bento, (address));
        barFeeTo = abi.decode(_barFeeTo, (address));
        swapFee = _swapFee;
        masterDeployer = _masterDeployer;
        unlocked = 1;
    }

    function mint(bytes calldata data) public override lock returns (uint256 liquidity) {
        (address recipient, uint256 toMint) = abi.decode(data, (address, uint256));
        
        uint256 ratio = div(toMint, totalSupply);

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenIn = tokens[i];
            uint256 balance = records[tokenIn].balance;
            // @dev If token balance is '0', initialize with `ratio`.
            uint256 amountIn = balance != 0 ? mul(ratio, balance) : ratio;
            require(amountIn >= MIN_BALANCE, "MIN_BALANCE");
            // @dev Check Trident router has sent amount for skim into pool.
            require(_balance(tokenIn) >= amountIn + balance, "NOT_RECEIVED");
            records[tokenIn].balance += amountIn;
            emit Mint(msg.sender, tokenIn, amountIn, recipient);
        }

        _mint(recipient, toMint);
        liquidity = toMint;
    }

    function burn(bytes calldata data) public override lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (address recipient, bool unwrapBento, uint256 toBurn) = abi.decode(data, (address, bool, uint256));
        
        uint256 ratio = div(toBurn, totalSupply);
        
        _burn(address(this), toBurn);
        
        withdrawnAmounts = new TokenAmount[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenOut = tokens[i];
            uint256 balance = records[tokenOut].balance;
            uint256 amountOut = mul(ratio, balance);
            require(amountOut != 0, "MATH_APPROX");
            records[tokenOut].balance -= amountOut;
            _transfer(tokenOut, amountOut, recipient, unwrapBento);
            withdrawnAmounts[i] = TokenAmount({token: tokenOut, amount: amountOut});
            emit Burn(msg.sender, tokenOut, amountOut, recipient);
        }
    }

    function burnSingle(bytes calldata data) public override lock returns (uint256 amount) {
        (address tokenOut, address recipient, bool unwrapBento, uint256 toBurn) = abi.decode(
            data,
            (address, address, bool, uint256)
        );

        Record storage outRecord = records[tokenOut];

        require(outRecord.set, "NOT_SET");

        amount = _computeSingleOutGivenPoolIn(
            outRecord.balance,
            outRecord.weight,
            totalSupply,
            totalWeight,
            toBurn,
            swapFee
        );

        require(amount <= mul(outRecord.balance, MAX_OUT_RATIO), "MAX_OUT_RATIO");

        outRecord.balance -= amount;

        _burn(address(this), toBurn);
        _transfer(tokenOut, amount, recipient, unwrapBento);

        emit Burn(msg.sender, tokenOut, amount, recipient);
    }

    function swap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountIn) = abi.decode(
            data,
            (address, address, address, bool, uint256)
        );

        require(records[tokenIn].set && records[tokenOut].set, "NOT_SET");

        Record storage inRecord = records[tokenIn];
        Record storage outRecord = records[tokenOut];

        require(amountIn <= mul(inRecord.balance, MAX_IN_RATIO), "MAX_IN_RATIO");

        amountOut = _getAmountOut(inRecord.balance, inRecord.weight, outRecord.balance, outRecord.weight, amountIn);
        // @dev Check Trident router has sent amount for skim into pool.
        require(_balance(tokenIn) >= amountIn + inRecord.balance, "NOT_RECEIVED");

        inRecord.balance += amountIn;
        outRecord.balance -= amountOut;

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

        require(records[tokenIn].set && records[tokenOut].set, "NOT_SET");

        Record storage inRecord = records[tokenIn];
        Record storage outRecord = records[tokenOut];

        require(amountIn <= mul(inRecord.balance, MAX_IN_RATIO), "MAX_IN_RATIO");

        amountOut = _getAmountOut(inRecord.balance, inRecord.weight, outRecord.balance, outRecord.weight, amountIn);
        ITridentCallee(msg.sender).tridentSwapCallback(context);
        // @dev Check Trident router has sent amount for skim into pool.
        require(_balance(tokenIn) >= amountIn + inRecord.balance, "NOT_RECEIVED");

        inRecord.balance += amountIn;
        outRecord.balance -= amountOut;

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
            // @dev withdraw(address,address,address,uint256,uint256).
            (bool success, ) = bento.call(abi.encodeWithSelector(0x97da6d30, token, address(this), to, 0, shares)); 
            require(success, "WITHDRAW_FAILED");
        } else {
            // @dev transfer(address,address,address,uint256).
            (bool success, ) = bento.call(abi.encodeWithSelector(0xf18d03cc, token, address(this), to, shares));
            require(success, "TRANSFER_FAILED");
        }
    }

    function _balance(address token) internal view returns (uint256 balance) {
        // @dev balanceOf(address,address).
        (, bytes memory data) = bento.staticcall(abi.encodeWithSelector(0xf7888aec, token, address(this)));
        balance = abi.decode(data, (uint256));
    }

    function _getAmountOut(
        uint256 tokenInBalance,
        uint256 tokenInWeight,
        uint256 tokenOutBalance,
        uint256 tokenOutWeight,
        uint256 tokenInAmount
    ) internal view returns (uint256 amountOut) {
        uint256 weightRatio = div(tokenInWeight, tokenOutWeight);
        uint256 adjustedIn = mul(tokenInAmount, (BASE - swapFee));
        
        uint256 a = div(tokenInBalance, tokenInBalance + adjustedIn);
        uint256 b = _compute(a, weightRatio);
        uint256 c = BASE - b;
        
        amountOut = mul(tokenOutBalance, c);
    }

    function _compute(uint256 base, uint256 exp) internal pure returns (uint256 output) {
        require(MIN_POW_BASE <= base && base <= MAX_POW_BASE, "INVALID_BASE");
        
        uint256 whole = (exp / BASE) * BASE;   
        uint256 remain = exp - whole;
        uint256 wholePow = _pow(base, whole / BASE);
        
        if (remain == 0) output = wholePow;
        
        uint256 partialResult = _powApprox(base, remain, POW_PRECISION);
        
        output = mul(wholePow, partialResult);
    }

    function _computeSingleOutGivenPoolIn(
        uint256 tokenOutBalance,
        uint256 tokenOutWeight,
        uint256 _totalSupply,
        uint256 _totalWeight,
        uint256 toBurn,
        uint256 _swapFee
    ) internal pure returns (uint256 amountOut) {
        uint256 normalizedWeight = div(tokenOutWeight, _totalWeight);
        uint256 newPoolSupply = _totalSupply - toBurn;
        uint256 poolRatio = div(newPoolSupply, _totalSupply);
        uint256 tokenOutRatio = _pow(poolRatio, div(BASE, normalizedWeight));
        uint256 newBalanceOut = mul(tokenOutRatio, tokenOutBalance);
        uint256 tokenAmountOutBeforeSwapFee = tokenOutBalance - newBalanceOut;
        uint256 zaz = (BASE - normalizedWeight) * _swapFee;
        amountOut = mul(tokenAmountOutBeforeSwapFee, (BASE - zaz));
    }
    
    function _pow(uint256 a, uint256 n) internal pure returns (uint256 output) {
        output = n % 2 != 0 ? a : BASE;
        for (n /= 2; n != 0; n /= 2) 
            a = a * a;
            if (n % 2 != 0) output = output * a;
    }
    
    function _powApprox(uint256 base, uint256 exp, uint256 precision) internal pure returns (uint256 sum) {
        uint256 a = exp;
        (uint256 x, bool xneg) = subFlag(base, BASE);
        uint256 term = BASE;
        sum = term;
        bool negative;

        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * BASE;
            (uint256 c, bool cneg) = subFlag(a, (bigK - BASE));
            term = mul(term, mul(c, x));
            term = div(term, bigK);
            if (term == 0) break;
            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = sum - term;
            } else {
                sum = sum + term;
            }
        }
    }
    
    function subFlag(uint256 a, uint256 b) internal pure returns (uint256 difference, bool flag) {
        unchecked {
            if (a >= b) {
                (difference, flag) = (a - b, false);
            } else {
                (difference, flag) = (b - a, true);
            }
        }
    }
    
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c2) {
        unchecked {
            uint256 c0 = a * b;
            require(a == 0 || c0 / a == b, "MUL_OVERFLOW");
            uint256 c1 = c0 + (BASE / 2);
            require(c1 >= c0, "MUL_OVERFLOW");
            c2 = c1 / BASE;
        }
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256 c2) {
        unchecked {
            require(b != 0, "DIV_ZERO");
            uint256 c0 = a * BASE;
            require(a == 0 || c0 / a == BASE, "DIV_INTERNAL"); 
            uint256 c1 = c0 + (b / 2);
            require(c1 >= c0, "DIV_INTERNAL"); 
            c2 = c1 / b;
        }
    }
    
    function getAmountOut(bytes calldata data) public view override returns (uint256 amountOut) {
        (
            uint256 tokenInBalance,
            uint256 tokenInWeight,
            uint256 tokenOutBalance,
            uint256 tokenOutWeight,
            uint256 tokenInAmount
        ) = abi.decode(data, (uint256, uint256, uint256, uint256, uint256));
        amountOut = _getAmountOut(tokenInBalance, tokenInWeight, tokenOutBalance, tokenOutWeight, tokenInAmount);
    }

    function getAssets() public view override returns (address[] memory assets) {
        assets = tokens;
    }
}

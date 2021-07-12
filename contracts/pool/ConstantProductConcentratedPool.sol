// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../base/Multicall.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IBentoBox.sol";
import "../interfaces/IMirinCallee.sol";
import "../libraries/MirinMath.sol";
import "../deployer/MasterDeployer.sol";

/// @notice Virtual NFTs for `Tripoint` liquidity positions on extended ERC20 interface.
/// @author Ross Campbell
contract TriPtToken {
    string public constant name = "Trident";
    string public constant symbol = "TRIDENT";
    uint8 public decimals;

    uint256 public totalSupply; // tracks total unique liquidity `triPts` 
    mapping(address => uint256) public balanceOf; // tracks `triPts` held by an account
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public immutable DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;
    
    mapping(uint256 => mapping(uint256 => Tripoint)) public triPts; // tracks liquidity updates in `Tripoint` range

    struct Tripoint { // virtual pool in liquidity `triPts` range (lo| |hi)
        uint112 reserve0; // last token0 balance
        uint112 reserve1; // last token1 balance
        uint256 totalSupply; // total for pool providers
        mapping(address => uint256) balanceOf; // account provider balance
    }

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function _mint(
        uint256 loPt, 
        uint256 hiPt, 
        address to, 
        uint256 value
    ) internal {
        triPts[loPt][hiPt].totalSupply += value;
        triPts[loPt][hiPt].balanceOf[to] += value;
        if (triPts[loPt][hiPt].balanceOf[to] == 0) {
            totalSupply++;
            emit Transfer(address(0), to, 1); // notices opening position for an account
        }
    }

    function _burn(
        uint256 hiPt, 
        uint256 loPt, 
        address from, 
        uint256 value
    ) internal {
        triPts[loPt][hiPt].balanceOf[from] -= value;
        unchecked {
            triPts[loPt][hiPt].totalSupply -= value;
        }
        if (triPts[loPt][hiPt].balanceOf[from] == 0) {
            totalSupply--;
            emit Transfer(from, address(0), 1); // notices closing position for an account
        }
    }

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) private {
        balanceOf[from] -= value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _transferFrom(
        address from,
        address to,
        uint256 value
    ) private {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        _transferFrom(from, to, value);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "MIRIN: EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "MIRIN: INVALID_SIGNATURE");
        _approve(owner, spender, value);
    }
}

abstract contract ConstantProductConcentratedPool is Multicall, TriPtToken, IPool {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;

    uint8 internal constant PRECISION = 112;
    uint256 internal constant MAX_FEE = 10000; // 100%
    uint256 internal constant MAX_FEE_SQUARE = 100000000;
    uint256 public immutable swapFee;
    uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE;

    address public immutable barFeeTo;

    IBentoBoxV1 private immutable bento;
    MasterDeployer public immutable masterDeployer;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "MIRIN: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /// @dev
    /// Only set immutable variables here. State changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (IERC20 tokenA, IERC20 tokenB, uint256 _swapFee) = abi.decode(_deployData, (IERC20, IERC20, uint256));

        require(address(tokenA) != address(0), "MIRIN: ZERO_ADDRESS");
        require(address(tokenB) != address(0), "MIRIN: ZERO_ADDRESS");
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "MIRIN: INVALID_SWAP_FEE");

        (IERC20 _token0, IERC20 _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxV1(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
    }

    function mint(uint256 loPt, uint256 hiPt, address to) public lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        (uint112 _triPtReserve0, uint112 _triPtReserve1) = _getTriPtReserves(loPt, hiPt); // gas savings
        
        uint256 _totalSupply = triPts[loPt][hiPt].totalSupply; // gas savings
        _mintFee(loPt, hiPt, _triPtReserve0, _triPtReserve1, _totalSupply);

        (uint256 balance0, uint256 balance1) = _balance(); // gas savings
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        uint256 triPtbalance0 = _triPtReserve0 + amount0;
        uint256 triPtbalance1 = _triPtReserve1 + amount1;

        uint256 computed = MirinMath.sqrt(triPtbalance0 * triPtbalance1);
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(loPt, hiPt, address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 k = MirinMath.sqrt(uint256(_triPtReserve0) * _triPtReserve1);
            liquidity = ((computed - k) * _totalSupply) / k;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(loPt, hiPt, to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Mint(msg.sender, amount0, amount1, to);
    }
    
    function burn(uint256 loPt, uint256 hiPt, address to) public lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _triPtReserve0, uint112 _triPtreserve1) = _getTriPtReserves(loPt, hiPt); // gas savings
        uint256 _totalSupply = triPts[loPt][hiPt].totalSupply; // gas savings
        _mintFee(loPt, hiPt, _triPtReserve0, _triPtreserve1, _totalSupply);

        uint256 liquidity = triPts[loPt][hiPt].balanceOf[address(this)]; // gas savings
        
        amount0 = (liquidity * _triPtReserve0) / _totalSupply;
        amount1 = (liquidity * _triPtreserve1) / _totalSupply;

        _burn(loPt, hiPt, address(this), liquidity);

        bento.transfer(token0, address(this), to, amount0);
        bento.transfer(token1, address(this), to, amount1);

        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        (uint256 balance0, uint256 balance1) = _balance(); // gas savings

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }
    // TO-DO: abstract lo/pt params (rn for testing format) -- need to calculate range, crossed liquidity
    function swapWithoutContext(
        uint256 loPt,
        uint256 hiPt,
        address tokenIn,
        address tokenOut,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        uint256 amountOut
    ) external returns (uint256) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        (uint112 _triPtReserve0, uint112 _triPtreserve1) = _getTriPtReserves(loPt, hiPt); // gas savings

        if (tokenIn == address(token0)) {
            require(tokenOut == address(token1), "Invalid output token");
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _triPtReserve0, _triPtreserve1);
            _swapWithOutData(0, amountOut, recipient, unwrapBento, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _triPtreserve1, _triPtReserve0);
            _swapWithOutData(amountOut, 0, recipient, unwrapBento, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
        }

        return amountOut;
    }

    function swapExactIn(
        uint256 loPt,
        uint256 hiPt,
        address tokenIn,
        address tokenOut,
        address recipient,
        bool unwrapBento,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        (uint112 _triPtReserve0, uint112 _triPtreserve1) = _getTriPtReserves(loPt, hiPt); // gas savings

        if (tokenIn == address(token0)) {
            require(tokenOut == address(token1), "Invalid output token");
            amountOut = _getAmountOut(amountIn, _triPtReserve0, _triPtreserve1);
            _swapWithOutData(0, amountOut, recipient, unwrapBento, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");
            amountOut = _getAmountOut(amountIn, _triPtreserve1, _triPtReserve0);
            _swapWithOutData(amountOut, 0, recipient, unwrapBento, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
        }
    }

    function swapExactOut(
        uint256 loPt,
        uint256 hiPt,
        address tokenIn,
        address tokenOut,
        address recipient,
        bool unwrapBento,
        uint256 amountOut
    ) external {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        (uint112 _triPtReserve0, uint112 _triPtreserve1) = _getTriPtReserves(loPt, hiPt); // gas savings

        if (tokenIn == address(token0)) {
            require(tokenOut == address(token1), "Invalid output token");
           _swapWithOutData(0, amountOut, recipient, unwrapBento, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
        } else {
            require(tokenIn == address(token1), "Invalid input token");
            require(tokenOut == address(token0), "Invalid output token");
            _swapWithOutData(amountOut, 0, recipient, unwrapBento, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
        }
    }

    function swapWithContext(
        uint256 loPt,
        uint256 hiPt,
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        bool unwrapBento,
        uint256 amountIn,
        uint256 amountOut
    ) public returns (uint256) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        (uint112 _triPtReserve0, uint112 _triPtreserve1) = _getTriPtReserves(loPt, hiPt); // gas savings

        if (tokenIn == address(token0)) {
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _triPtReserve0, _triPtreserve1);
            require(tokenOut == address(token1), "Invalid output token");
            _swapWithData(0, amountOut, recipient, unwrapBento, context, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
        } else if (tokenIn == address(token1)) {
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _triPtreserve1, _triPtReserve0);
            require(tokenOut == address(token0), "Invalid output token");
            _swapWithData(amountOut, 0, recipient, unwrapBento, context, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
        } else {
            require(tokenIn == address(this), "Invalid input token");
            require(tokenOut == address(token0) || tokenOut == address(token1), "Invalid output token");
            amountOut = _burnLiquiditySingle(
                loPt,
                hiPt,
                amountIn,
                amountOut,
                tokenOut,
                recipient,
                context,
                _reserve0,
                _reserve1,
                _blockTimestampLast
            );
        }

        return amountOut;
    }

    function swap(
        uint256 loPt,
        uint256 hiPt,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        (uint112 _triPtReserve0, uint112 _triPtreserve1) = _getTriPtReserves(loPt, hiPt); // gas savings
        _swapWithData(amount0Out, amount1Out, to, false, data, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
    }

    function _getReserves()
        internal
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
    
    function _getTriPtReserves(uint256 loPt, uint256 hiPt)
        internal
        view
        returns (
            uint112 _triPtReserve0,
            uint112 _triPtreserve1
        )
    {
        _triPtReserve0 = triPts[loPt][hiPt].reserve0;
        _triPtreserve1 = triPts[loPt][hiPt].reserve1;
    }

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "MIRIN: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        if (blockTimestamp != _blockTimestampLast && _reserve0 != 0) {
            unchecked {
                uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
                uint256 price0 = (uint256(_reserve1) << PRECISION) / _reserve0;
                price0CumulativeLast += price0 * timeElapsed;
                uint256 price1 = (uint256(_reserve0) << PRECISION) / _reserve1;
                price1CumulativeLast += price1 * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
    }

    function _mintFee(
        uint256 loPt,
        uint256 hiPt,
        uint112 _reserve0,
        uint112 _reserve1,
        uint256 _totalSupply
    ) private returns (uint256 computed) {
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            computed = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
            if (computed > _kLast) {
                // barFee % of increase in liquidity
                // NB It's going to be slihgtly less than barFee % in reality due to the Math
                uint256 barFee = MasterDeployer(masterDeployer).barFee();
                uint256 liquidity = (_totalSupply * (computed - _kLast) * barFee) / computed / MAX_FEE;
                if (liquidity > 0) {
                    _mint(loPt, hiPt, barFeeTo, liquidity);
                }
            }
        }
    }
    // TO-DO
    function _burnLiquiditySingle(
        uint256 loPt,
        uint256 hiPt,
        uint256 amountIn,
        uint256 amountOut,
        address tokenOut,
        address to,
        bytes calldata data,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) internal returns (uint256 finalAmountOut) {
        uint256 _totalSupply = totalSupply;
        _mintFee(loPt, hiPt, _reserve0, _reserve1, _totalSupply);

        uint256 amount0;
        uint256 amount1;
        uint256 liquidity;

        if (amountIn > 0) {
            finalAmountOut = _getOutAmountForBurn(tokenOut, amountIn, _totalSupply, _reserve0, _reserve1);

            if (tokenOut == address(token0)) {
                amount0 = finalAmountOut;
            } else {
                amount1 = finalAmountOut;
            }

            _transferWithoutData(amount0, amount1, to, false);
            if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0, amount1, data);

            liquidity = balanceOf[address(this)];
            require(liquidity >= amountIn, "Insufficient liquidity burned");
        } else {
            if (tokenOut == address(token0)) {
                amount0 = amountOut;
            } else {
                amount1 = amountOut;
            }

            _transferWithoutData(amount0, amount1, to, false);
            if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0, amount1, data);
            finalAmountOut = amountOut;

            liquidity = balanceOf[address(this)];
            uint256 allowedAmountOut = _getOutAmountForBurn(tokenOut, liquidity, _totalSupply, _reserve0, _reserve1);
            require(finalAmountOut <= allowedAmountOut, "Insufficient liquidity burned");
        }

        _burn(loPt, hiPt, address(this), liquidity);

        (uint256 balance0, uint256 balance1) = _balance();
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);

        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }
    // TO-DO
    function _getOutAmountForBurn(
        address tokenOut,
        uint256 liquidity,
        uint256 _totalSupply,
        uint112 _reserve0,
        uint112 _reserve1
    ) internal view returns (uint256 amount) {
        uint256 amount0 = (liquidity * _reserve0) / _totalSupply;
        uint256 amount1 = (liquidity * _reserve1) / _totalSupply;
        if (tokenOut == address(token0)) {
            amount0 += _getAmountOut(amount1, _reserve1 - amount1, _reserve0 - amount0);
            return amount0;
        } else {
            amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1);
            return amount1;
        }
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = bento.balanceOf(token0, address(this));
        balance1 = bento.balanceOf(token1, address(this));
    }

    function _compute(
        uint256 amount0In,
        uint256 amount1In,
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) internal view {
        uint256 balance0Adjusted = balance0 * MAX_FEE - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * MAX_FEE - amount1In * swapFee;
        require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * MAX_FEE_SQUARE, "MIRIN: LIQUIDITY");
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * MAX_FEE_MINUS_SWAP_FEE;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * MAX_FEE + amountInWithFee);
    }

    function _transferWithoutData(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bool unwrapBento
    ) internal {
        if (amount0Out > 0) {
            if (unwrapBento) {
                IBentoBoxV1(bento).withdraw(token0, address(this), to, amount0Out, 0);
            } else {
                bento.transfer(token0, address(this), to, bento.toShare(token0, amount0Out, false));
            }
        }
        if (amount1Out > 0) {
            if (unwrapBento) {
                IBentoBoxV1(bento).withdraw(token1, address(this), to, amount1Out, 0);
            } else {
                bento.transfer(token1, address(this), to, bento.toShare(token1, amount1Out, false));
            }
        }
    }

    function _swapWithData(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bool unwrapBento,
        bytes calldata data,
        uint112 _reserve0,
        uint112 _reserve1,
        uint112 _triPtReserve0,
        uint112 _triPtreserve1,
        uint32 _blockTimestampLast
    ) internal lock {
        _transferWithoutData(amount0Out, amount1Out, to, unwrapBento);
        if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0Out, amount1Out, data);
        _swap(amount0Out, amount1Out, to, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
    }

    function _swapWithOutData(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bool unwrapBento,
        uint112 _reserve0,
        uint112 _reserve1,
        uint112 _triPtReserve0,
        uint112 _triPtreserve1,
        uint32 _blockTimestampLast
    ) internal lock {
        _transferWithoutData(amount0Out, amount1Out, to, unwrapBento);
        _swap(amount0Out, amount1Out, to, _reserve0, _reserve1, _triPtReserve0, _triPtreserve1, _blockTimestampLast);
    }

    function _swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        uint112 _reserve0,
        uint112 _reserve1,
        uint112 _triPtReserve0,
        uint112 _triPtreserve1,
        uint32 _blockTimestampLast
    ) internal {
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0In = balance0 + amount0Out - _reserve0;
        uint256 amount1In = balance1 + amount1Out - _reserve1;
        uint256 triPtbalance0 = _triPtReserve0 + amount0In;
        uint256 triPtbalance1 = _triPtreserve1 + amount1In;
        _compute(amount0In, amount1In, triPtbalance0, triPtbalance1, _triPtReserve0, _triPtreserve1);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        (uint256 balance0, uint256 balance1) = _balance();
        bento.transfer(token0, address(this), to, bento.toShare(token0, balance0 - reserve0, false));
        bento.transfer(token1, address(this), to, bento.toShare(token1, balance1 - reserve1, false));
    }

    function sync() external lock {
        (uint256 balance0, uint256 balance1) = _balance();
        _update(balance0, balance1, reserve0, reserve1, blockTimestampLast);
    }

    function getAmountOut(
        uint256 loPt,
        uint256 hiPt,
        address tokenIn, 
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        (uint112 _triPtReserve0, uint112 _triPtreserve1) = _getTriPtReserves(loPt, hiPt); // gas savings
        if (IERC20(tokenIn) == token0) {
            amountOut = _getAmountOut(amountIn, _triPtReserve0, _triPtreserve1);
        } else {
            amountOut = _getAmountOut(amountIn, _triPtreserve1, _triPtReserve0);
        }
    }
    // TO-DO
    function getOptimalLiquidityInAmounts(liquidityInput[] memory liquidityInputs)
        external
        view
        override
        returns (liquidityAmount[] memory)
    {
        uint112 _reserve0;
        uint112 _reserve1;
        liquidityAmount[] memory liquidityOptimal = new liquidityAmount[](2);
        liquidityOptimal[0] = liquidityAmount({token: liquidityInputs[0].token, amount: liquidityInputs[0].amountDesired});
        liquidityOptimal[1] = liquidityAmount({token: liquidityInputs[1].token, amount: liquidityInputs[1].amountDesired});

        if (IERC20(liquidityInputs[0].token) == token0) {
            (_reserve0, _reserve1, ) = _getReserves();
        } else {
            (_reserve1, _reserve0, ) = _getReserves();
        }

        if (_reserve0 == 0 && _reserve1 == 0) {
            return liquidityOptimal;
        }

        uint256 amountBOptimal = (liquidityInputs[0].amountDesired * _reserve1) / _reserve0;
        if (amountBOptimal <= liquidityInputs[1].amountDesired) {
            require(amountBOptimal >= liquidityInputs[1].amountMin, "MIRIN: INSUFFICIENT_B_AMOUNT");
            liquidityOptimal[0].amount = liquidityInputs[0].amountDesired;
            liquidityOptimal[1].amount = amountBOptimal;
        } else {
            uint256 amountAOptimal = (liquidityInputs[1].amountDesired * _reserve0) / _reserve1;
            assert(amountAOptimal <= liquidityInputs[0].amountDesired);
            require(amountAOptimal >= liquidityInputs[0].amountMin, "MIRIN: INSUFFICIENT_A_AMOUNT");
            liquidityOptimal[0].amount = amountAOptimal;
            liquidityOptimal[1].amount = liquidityInputs[1].amountDesired;
        }

        return liquidityOptimal;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../interfaces/IPool.sol";
import "../interfaces/IBentoBox.sol";
import "../interfaces/IMirinCallee.sol";
import "../interfaces/IMerkleWhitelister.sol";
import "./MirinERC20.sol";
import "../libraries/MirinMath.sol";
import "hardhat/console.sol";
import "../deployer/MasterDeployer.sol";

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract ConstantProductFranchisedPool is MirinERC20, IPool {
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
    event Sync(uint112 reserve0, uint112 reserve1);

    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;

    uint8 internal constant PRECISION = 112;
    uint256 internal constant MAX_FEE = 10000; // 100%
    uint256 public immutable swapFee;

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
    
    bytes32 public override merkleRoot;
    address public operator;
    /// @dev This is a packed array of booleans.
    mapping(uint256 => uint256) private whitelistedBitMap;
    mapping(address => bool) private whitelisted;
    
    modifier whitelisted(address account) {
        require(whitelisted[account], '!whitelisted');
    }

    /// @dev
    /// Only set immutable variables here. State changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (IERC20 tokenA, IERC20 tokenB, uint256 _swapFee, bytes32 _merkleRoot, address _operator) =
            abi.decode(_deployData, (IERC20, IERC20, uint256, bytes32, address));

        require(address(tokenA) != address(0), "MIRIN: ZERO_ADDRESS");
        require(address(tokenB) != address(0), "MIRIN: ZERO_ADDRESS");
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "MIRIN: INVALID_SWAP_FEE");

        (IERC20 _token0, IERC20 _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        bento = IBentoBoxV1(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        merkleRoot = _merkleRoot;
        operator = _operator;
    }

    function init() public {
        require(totalSupply == 0);
        unlocked = 1;
    }
    
    /// @dev
    /// The following functions track merkle claims for whitelisting.
    function isWhitelisted(uint256 index) public view override returns (bool) {
        uint256 whitelistedWordIndex = index / 256;
        uint256 whitelistedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[whitelistedWordIndex];
        uint256 mask = (1 << whitelistedBitIndex);
        return claimedWord & mask == mask;
    }
    
    function joinWhitelist(uint256 index, address account, bytes32[] calldata merkleProof) external override {
        require(!isWhitelisted(index), 'Permission already claimed.');
        
        /// @dev Verify merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'Invalid proof');

        /// @dev Mark registration.
        _setWhitelisted(index);
        whitelisted[account] = true;

        emit JoinWhitelist(index, account);
    }
    
    function _setWhitelisted(uint256 index) private {
        uint256 whitelistedWordIndex = index / 256;
        uint256 whitelistedBitIndex = index % 256;
        whitelistedBitMap[whitelistedWordIndex] = whitelistedBitMap[whitelistedWordIndex] | (1 << whitelistedBitIndex);
    }
    
    function setMerkleRoot(bytes32 _merkleRoot) external {
        require(msg.sender == operator, '!operator');
        // Set the new merkle root
        merkleRoot = _merkleRoot;
        emit SetMerkleRoot(_merkleRoot);
    }

    function mint(address to) public override lock returns (uint256 liquidity) whitelisted(to) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);
        
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 computed = MirinMath.sqrt(balance0 * balance1);
        if (_totalSupply == 0) {
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 k = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
            liquidity = ((computed - k) * _totalSupply) / k;
        }
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, to);
    }

    function burn(address to) public lock returns (uint256 amount0, uint256 amount1) whitelisted(to) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        uint256 _totalSupply = totalSupply;
        _mintFee(_reserve0, _reserve1, _totalSupply);

        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _balance();
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);

        bento.transfer(token0, address(this), to, amount0);
        bento.transfer(token1, address(this), to, amount1);

        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        uint256 amountIn,
        uint256 amountOut
    ) public whitelisted(recipient) override returns (uint256) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings

        if (tokenIn == address(token0)) {
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            require(tokenOut == address(token1), "Invalid output token");
            _swap(0, amountOut, recipient, context, _reserve0, _reserve1, _blockTimestampLast);
        } else if (tokenIn == address(token1)) {
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            require(tokenOut == address(token0), "Invalid output token");
            _swap(amountOut, 0, recipient, context, _reserve0, _reserve1, _blockTimestampLast);
        } else {
            require(tokenIn == address(this), "Invalid input token");
            require(tokenOut == address(token0) || tokenOut == address(token1), "Invalid output token");
            amountOut = _burnLiquiditySingle(
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
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external whitelisted(to) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        _swap(amount0Out, amount1Out, to, data, _reserve0, _reserve1, _blockTimestampLast);
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

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "MIRIN: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        if (blockTimestamp != _blockTimestampLast && _reserve0 != 0 && _reserve1 != 0) {
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

        emit Sync(uint112(balance0), uint112(balance1));
    }

    function _mintFee(
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
                    _mint(barFeeTo, liquidity);
                }
            }
        }
    }

    function _burnLiquiditySingle(
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
        _mintFee(_reserve0, _reserve1, _totalSupply);

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

            _transferWithData(amount0, amount1, to, data);

            liquidity = balanceOf[address(this)];
            require(liquidity >= amountIn, "Insufficient liquidity burned");
        } else {
            if (tokenOut == address(token0)) {
                amount0 = amountOut;
            } else {
                amount1 = amountOut;
            }

            _transferWithData(amount0, amount1, to, data);
            finalAmountOut = amountOut;

            liquidity = balanceOf[address(this)];
            uint256 allowedAmountOut = _getOutAmountForBurn(tokenOut, liquidity, _totalSupply, _reserve0, _reserve1);
            require(finalAmountOut <= allowedAmountOut, "Insufficient liquidity burned");
        }

        _burn(address(this), liquidity);

        (uint256 balance0, uint256 balance1) = _balance();
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);

        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

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
        require(amount0In > 0 || amount1In > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        uint256 balance0Adjusted = balance0 * MAX_FEE - amount0In * swapFee;
        uint256 balance1Adjusted = balance1 * MAX_FEE - amount1In * swapFee;
        require(
            MirinMath.sqrt(balance0Adjusted * balance1Adjusted) >= MirinMath.sqrt(uint256(_reserve0) * _reserve1 * MAX_FEE * MAX_FEE),
            "MIRIN: LIQUIDITY"
        );
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view returns (uint256 amountOut) {
        require(amountIn > 0, "MIRIN: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "MIRIN: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * (MAX_FEE - swapFee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * MAX_FEE) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _transferWithData(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) internal {
        if (amount0Out > 0) bento.transfer(token0, address(this), to, bento.toShare(token0, amount0Out, false));
        if (amount1Out > 0) bento.transfer(token1, address(this), to, bento.toShare(token1, amount1Out, false));
        if (data.length > 0) IMirinCallee(to).mirinCall(msg.sender, amount0Out, amount1Out, data);
    }

    function _swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) internal lock {
        require(amount0Out > 0 || amount1Out > 0, "MIRIN: INSUFFICIENT_OUTPUT_AMOUNT");
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "MIRIN: INSUFFICIENT_LIQUIDITY");
        require(to != address(token0) && to != address(token1), "MIRIN: INVALID_TO");
        _transferWithData(amount0Out, amount1Out, to, data);

        uint256 amount0In;
        uint256 amount1In;
        {
            // scope for _balance{0,1} avoids stack too deep errors
            (uint256 balance0, uint256 balance1) = _balance();
            amount0In = balance0 + amount0Out - _reserve0;
            amount1In = balance1 + amount1Out - _reserve1;
            _compute(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);
            _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        }
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock whitelisted(to) {
        (uint256 balance0, uint256 balance1) = _balance();
        bento.transfer(token0, address(this), to, bento.toShare(token0, balance0 - reserve0, false));
        bento.transfer(token1, address(this), to, bento.toShare(token1, balance1 - reserve1, false));
    }

    function sync() external lock {
        (uint256 balance0, uint256 balance1) = _balance();
        _update(
            balance0,
            balance1,
            reserve0,
            reserve1,
            blockTimestampLast
        );
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        (uint112 _reserve0, uint112 _reserve1, ) = _getReserves();
        if (IERC20(tokenIn) == token0) {
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
        } else {
            amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
        }
    }

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

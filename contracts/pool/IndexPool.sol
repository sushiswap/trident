// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../deployer/MasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "../libraries/IndexMath.sol";
import "./TridentERC20.sol";
import "hardhat/console.sol";

/// @notice Trident exchange pool template with constant mean formula for swapping between an array of ERC-20 tokens.
/// @dev The reserves are stored as bento shares.
///      The curve is applied to shares as well. This pool does not care about the underlying amounts.
contract IndexPool is IPool, IndexMath, TridentERC20 {
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
    
    address[] private tokens;
    uint256 public totalWeight;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "IndexPool: LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }
    
    mapping(address => Record) public records;
    struct Record {
        bool bound;  
        uint256 index; 
        uint256 denorm;
        uint256 amount;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address[] memory _tokens, uint256[] memory _denorms, uint256 _swapFee) = abi.decode(
            _deployData,
            (address[], uint256[], uint256)
        );
        
        for (uint256 i = 0; i < tokens.length; i++) {
            require(_tokens[i] != address(0), "IndexPool: ZERO_ADDRESS");
            require(!records[_tokens[i]].bound, "IndexPool: BOUND");
            require(_denorms[i] >= MIN_WEIGHT, "IndexPool: MIN_WEIGHT");
            require(_denorms[i] <= MAX_WEIGHT, "IndexPool: MAX_WEIGHT");
            require(_tokens.length >= MIN_BOUND_TOKENS, "IndexPool: MIN_TOKENS");
            require(_tokens.length <= MAX_BOUND_TOKENS, "IndexPool: MAX_TOKENS");
            totalWeight = totalWeight + _denorms[i];
            require(totalWeight <= MAX_TOTAL_WEIGHT, "IndexPool: MAX_TOTAL_WEIGHT");
            records[_tokens[i]].bound = true;
            records[_tokens[i]].index = i;
            records[_tokens[i]].denorm = _denorms[i];
            tokens.push(_tokens[i]);
        }
        require(_swapFee <= MAX_FEE, "IndexPool: BAD_SWAP_FEE");
        _mint(tx.origin, INIT_POOL_SUPPLY); // @dev This grants pool deployer the initial LP supply.

        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxMinimal(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
    }
    
    function mint(bytes calldata data) public override lock returns (uint256 liquidity) {
        (uint256 toMint, uint256[] memory maxAmountsIn, address recipient) = abi.decode(
            data,
            (uint256, uint256[], address)
        );
        
        uint256 ratio = toMint / totalSupply;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenIn = tokens[i];
            uint256 amount = records[tokenIn].amount;
            uint256 amountIn = ratio * amount;
            require(amountIn >= MIN_BALANCE, "IndexPool: MIN_BALANCE");
            require(_getBentoBalance(tokenIn) >= amountIn + amount, "IndexPool: NOT_RECEIVED");
            require(amountIn <= maxAmountsIn[i], "IndexPool: LIMIT_IN"); // @dev Check Trident router has sent token amount for skim into pool.
            records[tokenIn].amount = records[tokenIn].amount + amountIn;
            emit Mint(msg.sender, tokenIn, amountIn, recipient);
        }
        
        _mint(recipient, toMint);
        liquidity = toMint;
    }
  
    function burn(bytes calldata data) public override lock returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        (uint256 toBurn, uint256[] memory minAmountsOut, address recipient, bool unwrapBento) = abi.decode(
            data,
            (uint256, uint256[], address, bool)
        );

        uint256 ratio = toBurn / totalSupply;

        _burn(address(this), toBurn);
        
        withdrawnAmounts = new TokenAmount[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenOut = tokens[i];
            uint256 amount = records[tokenOut].amount;
            uint256 amountOut = ratio * amount;
            require(amountOut != 0, "IndexPool: MATH_APPROX");
            require(amountOut >= minAmountsOut[i], "IndexPool: LIMIT_OUT");
            records[tokenOut].amount = records[tokenOut].amount - amountOut;
            _transfer(tokenOut, amountOut, recipient, unwrapBento);
            withdrawnAmounts[i] = TokenAmount({token: tokenOut, amount: amountOut});
            emit Burn(msg.sender, tokenOut, amountOut, recipient);
        }
    }
    
    function burnSingle(bytes calldata) public override lock returns (uint256 amount) {
        amount = 0;
    }

    function swap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (address tokenIn, address tokenOut, address recipient, bool unwrapBento, uint256 amountIn) = abi.decode(
            data,
            (address, address, address, bool, uint256)
        );
        
        require(records[tokenIn].bound, "IndexPool: NOT_BOUND");
        require(records[tokenOut].bound, "IndexPool: NOT_BOUND");
        
        Record storage inRecord = records[tokenIn];
        Record storage outRecord = records[tokenOut];
        
        require(amountIn <= inRecord.amount * MAX_IN_RATIO, "IndexPool: MAX_IN_RATIO");
        
        amountOut = _getAmountOut(
                            inRecord.amount,
                            inRecord.denorm,
                            outRecord.amount,
                            outRecord.denorm,
                            amountIn);

        inRecord.amount += amountIn;
        outRecord.amount -= amountOut;

        require(_getBentoBalance(tokenIn) >= amountIn + inRecord.amount, "IndexPool: NOT_RECEIVED"); // @dev Check Trident router has sent token amount for skim into pool.
        _transfer(tokenOut, amountOut, recipient, unwrapBento);

        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }
    
    function flashSwap(bytes calldata) public override lock returns (uint256 amountOut) {
        amountOut = 0;
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
 
    function _getBentoBalance(address token) internal view returns (uint256 balance) {
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
        uint256 adjustedIn = BONE - swapFee;
        adjustedIn = tokenAmountIn * adjustedIn;
        uint256 y = tokenBalanceIn / tokenBalanceIn + adjustedIn;
        uint256 foo = bpow(y, weightRatio);
        uint256 bar = BONE - foo;
        finalAmountOut = tokenBalanceOut * bar;
    }
    
    function getAmountOut(bytes calldata data) public view override returns (uint256 finalAmountOut) {
        (uint256 tokenBalanceIn, uint256 tokenWeightIn, uint256 tokenBalanceOut, uint256 tokenWeightOut, uint256 tokenAmountIn) 
        = abi.decode(data, (uint256, uint256, uint256, uint256, uint256));
        
       finalAmountOut = _getAmountOut(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn);
    }

    function getAssets() public view override returns (address[] memory assets) {
        assets = tokens;
    }
    
    function getNormalizedWeight(address asset) external view returns (uint256 norm) {
        norm = records[asset].denorm / totalWeight;
    }
    
    function getDenormalizedWeight(address asset) external view returns (uint256 denorm) {
        denorm = records[asset].denorm;
    }
}

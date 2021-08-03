// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../deployer/MasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "../libraries/BMath.sol";
import "../libraries/RebaseLibrary.sol";
import "./TridentERC20.sol";
import "hardhat/console.sol";

/// @notice Trident exchange pool template with constant mean formula for swapping between an array of ERC-20 tokens.
/// @dev This pool swaps between bento shares - it does not care about underlying amounts.
contract IndexPool is IPool, BMath, TridentERC20 {
    using RebaseLibrary for Rebase;

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
    
    address[] public assets;
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
        uint256 reserve;
        uint256 shares;
        Rebase total;
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address[] memory _assets, uint256[] memory _denorms, uint256 _swapFee) = abi.decode(
            _deployData,
            (address[], uint256[], uint256)
        );
        
        for (uint256 i = 0; i < assets.length; i++) {
            require(_assets[i] != address(0), "IndexPool: ZERO_ADDRESS");
            require(!records[_assets[i]].bound, "IndexPool: BOUND");
            require(_denorms[i] >= MIN_WEIGHT, "IndexPool: MIN_WEIGHT");
            require(_denorms[i] <= MAX_WEIGHT, "IndexPool: MAX_WEIGHT");
            totalWeight = badd(totalWeight, _denorms[i]);
            require(totalWeight <= MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");
            records[_assets[i]].bound = true;
            records[_assets[i]].index = i;
            records[_assets[i]].denorm = _denorms[i];
            assets.push(assets[i]);
        }
        require(_swapFee <= MAX_FEE, "IndexPool: BAD_SWAP_FEE");

        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxMinimal(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
    }
    
    function mint(bytes calldata data) public override lock returns (uint256 liquidity) {
        (uint256 liquidity, uint256[] memory maxAmountsIn, address recipient) = abi.decode(
            data,
            (uint256, uint256[], address)
        );
        
        uint256 ratio = bdiv(liquidity, totalSupply);
        require(ratio != 0, "IndexPool: MATH_APPROX");
        
        for (uint256 i = 0; i < assets.length; i++) {
            address tokenIn = assets[i];
            uint256 reserve = records[tokenIn].reserve;
            uint256 amountIn = bmul(ratio, reserve);
            require(amountIn >= MIN_BALANCE, "IndexPool: MIN_BALANCE");
            require(_getBalance(tokenIn) >= amountIn + reserve, "IndexPool: NOT_RECEIVED");
            require(amountIn <= maxAmountsIn[i], "IndexPool: LIMIT_IN");
            records[tokenIn].reserve = badd(records[tokenIn].reserve, amountIn);
            emit Mint(msg.sender, tokenIn, amountIn, recipient);
        }
        
        _mint(recipient, liquidity);
    }
  
    function burn(bytes calldata data) public override lock returns (TokenAmount[] memory withdrawnAmounts) {
        (uint256 poolAmountIn, uint256[] memory minAmountsOut, address recipient, bool unwrapBento) = abi.decode(
            data,
            (uint256, uint256[], address, bool)
        );

        uint256 ratio = bdiv(poolAmountIn, totalSupply);
        require(ratio != 0, "IndexPool: MATH_APPROX");

        _burn(address(this), poolAmountIn);

        for (uint256 i = 0; i < assets.length; i++) {
            address tokenOut = assets[i];
            uint256 reserve = records[tokenOut].reserve;
            uint256 amountOut = bmul(ratio, reserve);
            require(amountOut != 0, "IndexPool: MATH_APPROX");
            require(amountOut >= minAmountsOut[i], "IndexPool: LIMIT_OUT");
            records[tokenOut].reserve = bsub(records[tokenOut].reserve, amountOut);
            _transferShares(tokenOut, amountOut, recipient, unwrapBento);
            emit Burn(msg.sender, tokenOut, amountOut, recipient);
        }
    }

    function swap(bytes calldata data) public override lock returns (uint256 amountOut) {
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 maxPrice, address recipient, bool unwrapBento) = abi.decode(
            data,
            (address, address, uint256, uint256, uint256, address, bool)
        );
        
        require(records[tokenIn].bound, "IndexPool: NOT_BOUND");
        require(records[tokenOut].bound, "IndexPool: NOT_BOUND");
        
        Record storage inRecord = records[tokenIn];
        Record storage outRecord = records[tokenOut];
        
        require(amountIn <= bmul(inRecord.reserve, MAX_IN_RATIO), "IndexPool: MAX_IN_RATIO");
        
        uint256 spotPriceBefore = calcSpotPrice(
                                    inRecord.reserve,
                                    inRecord.denorm,
                                    outRecord.reserve,
                                    outRecord.denorm,
                                    swapFee);
        require(spotPriceBefore <= maxPrice, "IndexPool: BAD_LIMIT_PRICE");

        amountOut = calcOutGivenIn(
                            inRecord.reserve,
                            inRecord.denorm,
                            outRecord.reserve,
                            outRecord.denorm,
                            amountIn,
                            swapFee);
        require(amountOut >= minAmountOut, "IndexPool: LIMIT_OUT");

        inRecord.reserve = badd(inRecord.reserve, amountIn);
        outRecord.reserve = bsub(outRecord.reserve, amountOut);

        uint256 spotPriceAfter = calcSpotPrice(
                                inRecord.reserve,
                                inRecord.denorm,
                                outRecord.reserve,
                                outRecord.denorm,
                                swapFee);
        require(spotPriceAfter >= spotPriceBefore, "IndexPool: MATH_APPROX");     
        require(spotPriceAfter <= maxPrice, "IndexPool: LIMIT_PRICE");
        require(spotPriceBefore <= bdiv(amountIn, amountOut), "IndexPool: MATH_APPROX");

        require(_getBalance(tokenIn) >= amountIn + inRecord.reserve, "IndexPool: NOT_RECEIVED");
        _transferShares(tokenOut, amountOut, recipient, unwrapBento);

        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function _transferShares(
        address token,
        uint256 shares,
        address recipient,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token, address(this), recipient, 0, shares);
        } else {
            bento.transfer(token, address(this), recipient, shares);
        }
    }
 
    function _getBalance(address token) internal view returns (uint256 balance) {
        balance = bento.balanceOf(token, address(this));
    }
    
    function getNormalizedWeight(address asset) external view returns (uint256 norm) {
        norm = bdiv(records[asset].denorm, totalWeight);
    }
    
    function getDenormalizedWeight(address asset) external view returns (uint256 denorm) {
        denorm = records[asset].denorm;
    }
}

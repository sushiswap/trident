// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../deployer/MasterDeployer.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "../interfaces/IPool.sol";
import "../interfaces/ITridentCallee.sol";
import "../libraries/TridentMath.sol";
import "./TridentERC20.sol";
import "hardhat/console.sol";

abstract contract BColor {
    function getColor()
        external view virtual
        returns (bytes32);
}

contract BBronze is BColor {
    function getColor()
        external pure override
        returns (bytes32) {
            return bytes32("BRONZE");
        }
}

contract BConst is BBronze {
    uint256 public constant BONE              = 10**18;

    uint256 public constant MIN_BOUND_TOKENS  = 2;
    uint256 public constant MAX_BOUND_TOKENS  = 8;

    uint256 public constant MIN_FEE           = BONE / 10**6;
    // uint256 public constant MAX_FEE           = BONE / 10;
    uint256 public constant EXIT_FEE          = 0;

    uint256 public constant MIN_WEIGHT        = BONE;
    uint256 public constant MAX_WEIGHT        = BONE * 50;
    uint256 public constant MAX_TOTAL_WEIGHT  = BONE * 50;
    uint256 public constant MIN_BALANCE       = BONE / 10**12;

    uint256 public constant INIT_POOL_SUPPLY  = BONE * 100;

    uint256 public constant MIN_BPOW_BASE     = 1 wei;
    uint256 public constant MAX_BPOW_BASE     = (2 * BONE) - 1 wei;
    uint256 public constant BPOW_PRECISION    = BONE / 10**10;

    uint256 public constant MAX_IN_RATIO      = BONE / 2;
    uint256 public constant MAX_OUT_RATIO     = (BONE / 3) + 1 wei;
}

contract BNum is BConst {
    function btoi(uint256 a)
        internal pure 
        returns (uint256)
    {
        return a / BONE;
    }

    function bfloor(uint256 a)
        internal pure
        returns (uint256)
    {
        return btoi(a) * BONE;
    }

    function badd(uint256 a, uint256 b)
        internal pure
        returns (uint256)
    {
        uint c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function bsub(uint256 a, uint256 b)
        internal pure
        returns (uint256)
    {
        (uint256 c, bool flag) = bsubSign(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    function bsubSign(uint256 a, uint256 b)
        internal pure
        returns (uint256, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function bmul(uint a, uint b)
        internal pure
        returns (uint)
    {
        uint256 c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint256 c1 = c0 + (BONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint256 c2 = c1 / BONE;
        return c2;
    }

    function bdiv(uint256 a, uint256 b)
        internal pure
        returns (uint256)
    {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * BONE;
        require(a == 0 || c0 / a == BONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    // DSMath.wpow
    function bpowi(uint256 a, uint256 n)
        internal pure
        returns (uint256)
    {
        uint256 z = n % 2 != 0 ? a : BONE;
        for (n /= 2; n != 0; n /= 2) {
            a = bmul(a, a);
            if (n % 2 != 0) {
                z = bmul(z, a);
            }
        }
        return z;
    }

    // Compute b^(e.w) by splitting it into (b^e)*(b^0.w).
    // Use `bpowi` for `b^e` and `bpowK` for k iterations
    // of approximation of b^0.w
    function bpow(uint256 base, uint256 exp)
        internal pure
        returns (uint256)
    {
        require(base >= MIN_BPOW_BASE, "ERR_BPOW_BASE_TOO_LOW");
        require(base <= MAX_BPOW_BASE, "ERR_BPOW_BASE_TOO_HIGH");

        uint256 whole  = bfloor(exp);   
        uint256 remain = bsub(exp, whole);

        uint256 wholePow = bpowi(base, btoi(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint256 partialResult = bpowApprox(base, remain, BPOW_PRECISION);
        return bmul(wholePow, partialResult);
    }

    function bpowApprox(uint256 base, uint256 exp, uint256 precision)
        internal pure
        returns (uint256)
    {
        // term 0:
        uint256 a     = exp;
        (uint x, bool xneg)  = bsubSign(base, BONE);
        uint256 term = BONE;
        uint256 sum   = term;
        bool negative = false;

        // term(k) = numer / denom 
        //         = (product(a - i - 1, i=1-->k) * x^k) / (k!)
        // each iteration, multiply previous term by (a-(k-1)) * x / k
        // continue until term is less than precision
        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * BONE;
            (uint256 c, bool cneg) = bsubSign(a, bsub(bigK, BONE));
            term = bmul(term, bmul(c, x));
            term = bdiv(term, bigK);
            if (term == 0) break;

            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = bsub(sum, term);
            } else {
                sum = badd(sum, term);
            }
        }
        return sum;
    }
}

contract BMath is BBronze, BConst, BNum {
    /**********************************************************************************************
    // calcSpotPrice                                                                             //
    // sP = spotPrice                                                                            //
    // bI = tokenBalanceIn                ( bI / wI )         1                                  //
    // bO = tokenBalanceOut         sP =  -----------  *  ----------                             //
    // wI = tokenWeightIn                 ( bO / wO )     ( 1 - sF )                             //
    // wO = tokenWeightOut                                                                       //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcSpotPrice(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint swapFee
    )
        public pure
        returns (uint256 spotPrice)
    {
        uint256 numer = bdiv(tokenBalanceIn, tokenWeightIn);
        uint256 denom = bdiv(tokenBalanceOut, tokenWeightOut);
        uint256 ratio = bdiv(numer, denom);
        uint256 scale = bdiv(BONE, bsub(BONE, swapFee));
        return  (spotPrice = bmul(ratio, scale));
    }

    /**********************************************************************************************
    // calcOutGivenIn                                                                            //
    // aO = tokenAmountOut                                                                       //
    // bO = tokenBalanceOut                                                                      //
    // bI = tokenBalanceIn              /      /            bI             \    (wI / wO) \      //
    // aI = tokenAmountIn    aO = bO * |  1 - | --------------------------  | ^            |     //
    // wI = tokenWeightIn               \      \ ( bI + ( aI * ( 1 - sF )) /              /      //
    // wO = tokenWeightOut                                                                       //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcOutGivenIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountIn,
        uint256 swapFee
    )
        public pure
        returns (uint256 tokenAmountOut)
    {
        uint256 weightRatio = bdiv(tokenWeightIn, tokenWeightOut);
        uint256 adjustedIn = bsub(BONE, swapFee);
        adjustedIn = bmul(tokenAmountIn, adjustedIn);
        uint256 y = bdiv(tokenBalanceIn, badd(tokenBalanceIn, adjustedIn));
        uint256 foo = bpow(y, weightRatio);
        uint256 bar = bsub(BONE, foo);
        tokenAmountOut = bmul(tokenBalanceOut, bar);
        return tokenAmountOut;
    }

    /**********************************************************************************************
    // calcInGivenOut                                                                            //
    // aI = tokenAmountIn                                                                        //
    // bO = tokenBalanceOut               /  /     bO      \    (wO / wI)      \                 //
    // bI = tokenBalanceIn          bI * |  | ------------  | ^            - 1  |                //
    // aO = tokenAmountOut    aI =        \  \ ( bO - aO ) /                   /                 //
    // wI = tokenWeightIn           --------------------------------------------                 //
    // wO = tokenWeightOut                          ( 1 - sF )                                   //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcInGivenOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountOut,
        uint256 swapFee
    )
        public pure
        returns (uint256 tokenAmountIn)
    {
        uint256 weightRatio = bdiv(tokenWeightOut, tokenWeightIn);
        uint256 diff = bsub(tokenBalanceOut, tokenAmountOut);
        uint256 y = bdiv(tokenBalanceOut, diff);
        uint256 foo = bpow(y, weightRatio);
        foo = bsub(foo, BONE);
        tokenAmountIn = bsub(BONE, swapFee);
        tokenAmountIn = bdiv(bmul(tokenBalanceIn, foo), tokenAmountIn);
        return tokenAmountIn;
    }

    /**********************************************************************************************
    // calcPoolOutGivenSingleIn                                                                  //
    // pAo = poolAmountOut         /                                              \              //
    // tAi = tokenAmountIn        ///      /     //    wI \      \\       \     wI \             //
    // wI = tokenWeightIn        //| tAi *| 1 - || 1 - --  | * sF || + tBi \    --  \            //
    // tW = totalWeight     pAo=||  \      \     \\    tW /      //         | ^ tW   | * pS - pS //
    // tBi = tokenBalanceIn      \\  ------------------------------------- /        /            //
    // pS = poolSupply            \\                    tBi               /        /             //
    // sF = swapFee                \                                              /              //
    **********************************************************************************************/
    function calcPoolOutGivenSingleIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 tokenAmountIn,
        uint256 swapFee
    )
        public pure
        returns (uint256 poolAmountOut)
    {
        // Charge the trading fee for the proportion of tokenAi
        ///  which is implicitly traded to the other pool tokens.
        // That proportion is (1- weightTokenIn)
        // tokenAiAfterFee = tAi * (1 - (1-weightTi) * poolFee);
        uint256 normalizedWeight = bdiv(tokenWeightIn, totalWeight);
        uint256 zaz = bmul(bsub(BONE, normalizedWeight), swapFee); 
        uint256 tokenAmountInAfterFee = bmul(tokenAmountIn, bsub(BONE, zaz));

        uint256 newTokenBalanceIn = badd(tokenBalanceIn, tokenAmountInAfterFee);
        uint256 tokenInRatio = bdiv(newTokenBalanceIn, tokenBalanceIn);

        // uint newPoolSupply = (ratioTi ^ weightTi) * poolSupply;
        uint256 poolRatio = bpow(tokenInRatio, normalizedWeight);
        uint256 newPoolSupply = bmul(poolRatio, poolSupply);
        poolAmountOut = bsub(newPoolSupply, poolSupply);
        return poolAmountOut;
    }

    /**********************************************************************************************
    // calcSingleInGivenPoolOut                                                                  //
    // tAi = tokenAmountIn              //(pS + pAo)\     /    1    \\                           //
    // pS = poolSupply                 || ---------  | ^ | --------- || * bI - bI                //
    // pAo = poolAmountOut              \\    pS    /     \(wI / tW)//                           //
    // bI = balanceIn          tAi =  --------------------------------------------               //
    // wI = weightIn                              /      wI  \                                   //
    // tW = totalWeight                          |  1 - ----  |  * sF                            //
    // sF = swapFee                               \      tW  /                                   //
    **********************************************************************************************/
    function calcSingleInGivenPoolOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 poolAmountOut,
        uint256 swapFee
    )
        public pure
        returns (uint256 tokenAmountIn)
    {
        uint256 normalizedWeight = bdiv(tokenWeightIn, totalWeight);
        uint256 newPoolSupply = badd(poolSupply, poolAmountOut);
        uint256 poolRatio = bdiv(newPoolSupply, poolSupply);
      
        //uint newBalTi = poolRatio^(1/weightTi) * balTi;
        uint256 boo = bdiv(BONE, normalizedWeight); 
        uint256 tokenInRatio = bpow(poolRatio, boo);
        uint256 newTokenBalanceIn = bmul(tokenInRatio, tokenBalanceIn);
        uint256 tokenAmountInAfterFee = bsub(newTokenBalanceIn, tokenBalanceIn);
        // Do reverse order of fees charged in joinswap_ExternAmountIn, this way 
        //     ``` pAo == joinswap_ExternAmountIn(Ti, joinswap_PoolAmountOut(pAo, Ti)) ```
        //uint tAi = tAiAfterFee / (1 - (1-weightTi) * swapFee) ;
        uint256 zar = bmul(bsub(BONE, normalizedWeight), swapFee);
        tokenAmountIn = bdiv(tokenAmountInAfterFee, bsub(BONE, zar));
        return tokenAmountIn;
    }

    /**********************************************************************************************
    // calcSingleOutGivenPoolIn                                                                  //
    // tAo = tokenAmountOut            /      /                                             \\   //
    // bO = tokenBalanceOut           /      // pS - (pAi * (1 - eF)) \     /    1    \      \\  //
    // pAi = poolAmountIn            | bO - || ----------------------- | ^ | --------- | * b0 || //
    // ps = poolSupply                \      \\          pS           /     \(wO / tW)/      //  //
    // wI = tokenWeightIn      tAo =   \      \                                             //   //
    // tW = totalWeight                    /     /      wO \       \                             //
    // sF = swapFee                    *  | 1 - |  1 - ---- | * sF  |                            //
    // eF = exitFee                        \     \      tW /       /                             //
    **********************************************************************************************/
    function calcSingleOutGivenPoolIn(
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 poolAmountIn,
        uint256 swapFee
    )
        public pure
        returns (uint256 tokenAmountOut)
    {
        uint256 normalizedWeight = bdiv(tokenWeightOut, totalWeight);
        // charge exit fee on the pool token side
        // pAiAfterExitFee = pAi*(1-exitFee)
        uint256 poolAmountInAfterExitFee = bmul(poolAmountIn, bsub(BONE, EXIT_FEE));
        uint256 newPoolSupply = bsub(poolSupply, poolAmountInAfterExitFee);
        uint256 poolRatio = bdiv(newPoolSupply, poolSupply);
     
        // newBalTo = poolRatio^(1/weightTo) * balTo;
        uint256 tokenOutRatio = bpow(poolRatio, bdiv(BONE, normalizedWeight));
        uint256 newTokenBalanceOut = bmul(tokenOutRatio, tokenBalanceOut);

        uint256 tokenAmountOutBeforeSwapFee = bsub(tokenBalanceOut, newTokenBalanceOut);

        // charge swap fee on the output token side 
        //uint tAo = tAoBeforeSwapFee * (1 - (1-weightTo) * swapFee)
        uint256 zaz = bmul(bsub(BONE, normalizedWeight), swapFee); 
        tokenAmountOut = bmul(tokenAmountOutBeforeSwapFee, bsub(BONE, zaz));
        return tokenAmountOut;
    }

    /**********************************************************************************************
    // calcPoolInGivenSingleOut                                                                  //
    // pAi = poolAmountIn               // /               tAo             \\     / wO \     \   //
    // bO = tokenBalanceOut            // | bO - -------------------------- |\   | ---- |     \  //
    // tAo = tokenAmountOut      pS - ||   \     1 - ((1 - (tO / tW)) * sF)/  | ^ \ tW /  * pS | //
    // ps = poolSupply                 \\ -----------------------------------/                /  //
    // wO = tokenWeightOut  pAi =       \\               bO                 /                /   //
    // tW = totalWeight           -------------------------------------------------------------  //
    // sF = swapFee                                        ( 1 - eF )                            //
    // eF = exitFee                                                                              //
    **********************************************************************************************/
    function calcPoolInGivenSingleOut(
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 tokenAmountOut,
        uint256 swapFee
    )
        public pure
        returns (uint256 poolAmountIn)
    {

        // charge swap fee on the output token side 
        uint256 normalizedWeight = bdiv(tokenWeightOut, totalWeight);
        //uint tAoBeforeSwapFee = tAo / (1 - (1-weightTo) * swapFee) ;
        uint256 zoo = bsub(BONE, normalizedWeight);
        uint256 zar = bmul(zoo, swapFee); 
        uint256 tokenAmountOutBeforeSwapFee = bdiv(tokenAmountOut, bsub(BONE, zar));

        uint256 newTokenBalanceOut = bsub(tokenBalanceOut, tokenAmountOutBeforeSwapFee);
        uint256 tokenOutRatio = bdiv(newTokenBalanceOut, tokenBalanceOut);

        //uint newPoolSupply = (ratioTo ^ weightTo) * poolSupply;
        uint256 poolRatio = bpow(tokenOutRatio, normalizedWeight);
        uint256 newPoolSupply = bmul(poolRatio, poolSupply);
        uint256 poolAmountInAfterExitFee = bsub(poolSupply, newPoolSupply);

        // charge exit fee on the pool token side
        // pAi = pAiAfterExitFee/(1-exitFee)
        poolAmountIn = bdiv(poolAmountInAfterExitFee, bsub(BONE, EXIT_FEE));
        return poolAmountIn;
    }
}

/// @notice Trident exchange pool template with constant mean formula for swapping between an array of ERC-20 tokens.
/// @dev This pool swaps between bento shares - it does not care about underlying amounts.
abstract contract IndexPool is IPool, BBronze, BMath, TridentERC20 {
    event Mint(address indexed sender, address tokenIn, uint256 amountIn, address indexed recipient);
    event Burn(address indexed sender, address tokenOut, uint256 amountOut, address indexed recipient);
    event Sync(uint256 reserve);

    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    uint8 internal constant PRECISION = 112;
    uint256 internal constant MAX_FEE = 10000; // @dev 100%.
    uint256 internal constant MAX_FEE_SQUARE = 100000000;
    uint256 public immutable swapFee;
    uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE;
    
    uint256 public totalWeight;

    address internal immutable barFeeTo;
    IBentoBoxMinimal internal immutable bento;
    MasterDeployer internal immutable masterDeployer;
    
    uint256 public constant override poolType = 4;
    address[] public assets;

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
    }

    /// @dev Only set immutable variables here - state changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (address[] memory _assets, uint256 _swapFee) = abi.decode(
            _deployData,
            (address[], uint256)
        );
        
        for (uint256 i = 0; i < assets.length; i++) {
            require(_assets[i] != address(0), "IndexPool: ZERO_ADDRESS");
            require(!records[_assets[i]].bound, "IndexPool: BOUND");
            records[_assets[i]].bound;
            assets.push(assets[i]);
        }
        require(_swapFee <= MAX_FEE, "IndexPool: INVALID_SWAP_FEE");

        swapFee = _swapFee;
        MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        bento = IBentoBoxMinimal(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
        unlocked = 1;
    }
    
    function mint(bytes calldata data) external override lock returns (uint256 poolAmountOut) {
        (uint256 poolAmountOut, uint256[] memory maxAmountsIn, address recipient) = abi.decode(
            data,
            (uint256, uint256[], address)
        );
        
        uint256 ratio = bdiv(poolAmountOut, totalSupply);
        require(ratio != 0, "IndexPool: ERR_MATH_APPROX");
        
        for (uint256 i = 0; i < assets.length; i++) {
            address tokenIn = assets[i];
            uint256 reserve = records[tokenIn].reserve;
            uint256 amountIn = bmul(ratio, reserve);
            require(amountIn != 0, "IndexPool: ERR_MATH_APPROX");
            require(amountIn <= maxAmountsIn[i], "IndexPool: ERR_LIMIT_IN");
            records[tokenIn].reserve = badd(records[tokenIn].reserve, amountIn);
            _pullToken(tokenIn, amountIn);
            emit Mint(msg.sender, tokenIn, amountIn, recipient);
        }
        
        _mint(recipient, poolAmountOut);
    }


    function burn(bytes calldata data) external override lock returns (TokenAmount[] memory withdrawnAmounts) {
        (uint256 poolAmountIn, uint256[] memory minAmountsOut, address recipient) = abi.decode(
            data,
            (uint256, uint256[], address)
        );

        uint256 ratio = bdiv(poolAmountIn, totalSupply);
        require(ratio != 0, "IndexPool: ERR_MATH_APPROX");

        _burn(address(this), poolAmountIn);

        for (uint256 i = 0; i < assets.length; i++) {
            address tokenOut = assets[i];
            uint256 reserve = records[tokenOut].reserve;
            uint256 amountOut = bmul(ratio, reserve);
            require(amountOut != 0, "IndexPool: ERR_MATH_APPROX");
            require(amountOut >= minAmountsOut[i], "IndexPool: ERR_LIMIT_OUT");
            records[tokenOut].reserve = bsub(records[tokenOut].reserve, amountOut);
            _pushToken(tokenOut, recipient, amountOut);
            emit Burn(msg.sender, tokenOut, amountOut, recipient);
        }
    }

    function swap(bytes calldata data) external override lock returns (uint256 amountOut) {
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 maxPrice, address recipient) = abi.decode(
            data,
            (address, address, uint256, uint256, uint256, address)
        );
        
        require(records[tokenIn].bound, "IndexPool: ERR_NOT_BOUND");
        require(records[tokenOut].bound, "IndexPool: ERR_NOT_BOUND");
        
        Record storage inRecord = records[tokenIn];
        Record storage outRecord = records[tokenOut];
        
        require(amountIn <= bmul(inRecord.reserve, MAX_IN_RATIO), "IndexPool: ERR_MAX_IN_RATIO");
        
        uint256 spotPriceBefore = calcSpotPrice(
                                    inRecord.reserve,
                                    inRecord.denorm,
                                    outRecord.reserve,
                                    outRecord.denorm,
                                    swapFee
                                );
        require(spotPriceBefore <= maxPrice, "IndexPool: ERR_BAD_LIMIT_PRICE");

        amountOut = calcOutGivenIn(
                            inRecord.reserve,
                            inRecord.denorm,
                            outRecord.reserve,
                            outRecord.denorm,
                            amountIn,
                            swapFee
                        );
        require(amountOut >= minAmountOut, "IndexPool: ERR_LIMIT_OUT");

        inRecord.reserve = badd(inRecord.reserve, amountIn);
        outRecord.reserve = bsub(outRecord.reserve, amountOut);

        uint256 spotPriceAfter = calcSpotPrice(
                                inRecord.reserve,
                                inRecord.denorm,
                                outRecord.reserve,
                                outRecord.denorm,
                                swapFee
                            );
        require(spotPriceAfter >= spotPriceBefore, "IndexPool: ERR_MATH_APPROX");     
        require(spotPriceAfter <= maxPrice, "IndexPool: ERR_LIMIT_PRICE");
        require(spotPriceBefore <= bdiv(amountIn, amountOut), "IndexPool: ERR_MATH_APPROX");

        _pullToken(tokenIn, amountIn);
        _pushToken(tokenOut, recipient, amountOut);

        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function _processSwap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata data,
        bool unwrapBento
    ) internal {
        _transfer(tokenOut, amountOut, to, unwrapBento);
        if (data.length > 0) ITridentCallee(to).tridentCallback(tokenIn, tokenOut, amountIn, amountOut, data);
    }

    function _balance(address token) internal view returns (uint256 balance) {
        balance = bento.balanceOf(token, address(this));
    }

    function _transfer(
        address token,
        uint256 amount,
        address to,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token, address(this), to, 0, amount);
        } else {
            bento.transfer(token, address(this), to, amount);
        }
    }
    
    function _pullToken(address token, uint256 amount) internal {
        bento.transfer(token, msg.sender, address(this), amount);
    }
    
    function _pushToken(address token, address recipient, uint256 amount) internal {
        bento.transfer(token, address(this), recipient, amount);
    }

    function getNormalizedWeight(address asset) external view returns (uint256 norm) {
        norm = bdiv(records[asset].denorm, totalWeight);
    }
    
    function getDenormalizedWeight(address asset) external view returns (uint256 denorm) {
        denorm = records[asset].denorm;
    }
}

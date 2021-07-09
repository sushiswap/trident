pragma solidity ^0.8.2;

interface IPool {
    struct liquidityInput {
        address token;
        bool native;
        uint256 amountDesired;
        uint256 amountMin;
    }

    struct liquidityInputOptimal {
        address token;
        bool native;
        uint256 amount;
    }

    struct liquidityAmount {
        address token;
        uint256 amount;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        uint256 amountIn,
        uint256 amountOut
    ) external returns (uint256 finalAmountOut);

    function getOptimalLiquidityInAmounts(liquidityInput[] calldata liquidityInputs)
        external
        returns (liquidityAmount[] memory liquidityOptimal);

    function mint(address to) external returns (uint256 liquidity);
}

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBentoBoxV1 {
    function balanceOf(IERC20, address) external view returns (uint256);

    function deposit(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);

    function withdraw(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);

    function transfer(
        IERC20 token,
        address from,
        address to,
        uint256 share
    ) external;

    function transferMultiple(
        IERC20 token,
        address from,
        address[] calldata tos,
        uint256[] calldata shares
    ) external;

    function toShare(
        IERC20 token,
        uint256 amount,
        bool roundUp
    ) external view returns (uint256 share);

    function toAmount(
        IERC20 token,
        uint256 share,
        bool roundUp
    ) external view returns (uint256 amount);

    function registerProtocol() external;
}

interface IMirinCallee {
    function mirinCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

/**
 * @dev Originally DeriswapV1Math
 * @author Andre Cronje, LevX
 */
library MirinMath {
    uint256 internal constant ONE = 1;
    uint256 internal constant FIXED_1 = 0x080000000000000000000000000000000;
    uint256 internal constant FIXED_2 = 0x100000000000000000000000000000000;
    uint256 internal constant SQRT_1 = 13043817825332782212;
    uint256 internal constant LNX = 3988425491;
    uint256 internal constant LOG_10_2 = 3010299957;
    uint256 internal constant LOG_E_2 = 6931471806;
    uint256 internal constant BASE10 = 1e10;

    uint256 internal constant MAX_NUM = 0x200000000000000000000000000000000;
    uint8 internal constant MIN_PRECISION = 32;
    uint8 internal constant MAX_PRECISION = 127;
    uint256 internal constant OPT_LOG_MAX_VAL = 0x15bf0a8b1457695355fb8ac404e7a79e3;
    uint256 internal constant OPT_EXP_MAX_VAL = 0x800000000000000000000000000000000;

    uint256 internal constant BASE18 = 1e18;
    uint256 internal constant MIN_POWER_BASE = 1 wei;
    uint256 internal constant MAX_POWER_BASE = (2 * BASE18) - 1 wei;
    uint256 internal constant POWER_PRECISION = BASE18 / 1e10;

    // computes square roots using the babylonian method
    // https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method
    // credit for this implementation goes to
    // https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol#L687
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        // this block is equivalent to r = uint256(1) << (BitMath.mostSignificantBit(x) / 2);
        // however that code costs significantly more gas
        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }

    function ln(uint256 x) internal pure returns (uint256) {
        uint256 res = 0;

        // If x >= 2, then we compute the integer part of log2(x), which is larger than 0.
        if (x >= FIXED_2) {
            uint8 count = floorLog2(x / FIXED_1);
            x >>= count; // now x < 2
            res = count * FIXED_1;
        }

        // If x > 1, then we compute the fraction part of log2(x), which is larger than 0.
        if (x > FIXED_1) {
            for (uint8 i = MAX_PRECISION; i > 0; --i) {
                x = (x * x) / FIXED_1; // now 1 < x < 4
                if (x >= FIXED_2) {
                    x >>= 1; // now 1 < x < 2
                    res += ONE << (i - 1);
                }
            }
        }

        return (res * LOG_E_2) / BASE10;
    }

    /**
     * @dev computes log(x / FIXED_1) * FIXED_1.
     * This functions assumes that "x >= FIXED_1", because the output would be negative otherwise.
     */
    function generalLog(uint256 x) internal pure returns (uint256) {
        uint256 res = 0;

        // If x >= 2, then we compute the integer part of log2(x), which is larger than 0.
        if (x >= FIXED_2) {
            uint8 count = floorLog2(x / FIXED_1);
            x >>= count; // now x < 2
            res = count * FIXED_1;
        }

        // If x > 1, then we compute the fraction part of log2(x), which is larger than 0.
        if (x > FIXED_1) {
            for (uint8 i = MAX_PRECISION; i > 0; --i) {
                x = (x * x) / FIXED_1; // now 1 < x < 4
                if (x >= FIXED_2) {
                    x >>= 1; // now 1 < x < 2
                    res += ONE << (i - 1);
                }
            }
        }

        return (res * LOG_10_2) / BASE10;
    }

    /**
     * @dev computes the largest integer smaller than or equal to the binary logarithm of the input.
     */
    function floorLog2(uint256 _n) internal pure returns (uint8) {
        uint8 res = 0;

        if (_n < 256) {
            // At most 8 iterations
            while (_n > 1) {
                _n >>= 1;
                res += 1;
            }
        } else {
            // Exactly 8 iterations
            for (uint8 s = 128; s > 0; s >>= 1) {
                if (_n >= (ONE << s)) {
                    _n >>= s;
                    res |= s;
                }
            }
        }

        return res;
    }

    /**
     * @dev computes ln(x / FIXED_1) * FIXED_1
     * Input range: FIXED_1 <= x <= OPT_LOG_MAX_VAL - 1
     * Auto-generated via 'PrintFunctionOptimalLog.py'
     * Detailed description:
     * - Rewrite the input as a product of natural exponents and a single residual r, such that 1 < r < 2
     * - The natural logarithm of each (pre-calculated) exponent is the degree of the exponent
     * - The natural logarithm of r is calculated via Taylor series for log(1 + x), where x = r - 1
     * - The natural logarithm of the input is calculated by summing up the intermediate results above
     * - For example: log(250) = log(e^4 * e^1 * e^0.5 * 1.021692859) = 4 + 1 + 0.5 + log(1 + 0.021692859)
     */
    function optimalLog(uint256 x) internal pure returns (uint256) {
        require(FIXED_1 <= x, "MIRIN: OVERFLOW");
        uint256 res = 0;

        uint256 y;
        uint256 z;
        uint256 w;

        if (x >= 0xd3094c70f034de4b96ff7d5b6f99fcd8) {
            res += 0x40000000000000000000000000000000;
            x = (x * FIXED_1) / 0xd3094c70f034de4b96ff7d5b6f99fcd8;
        } // add 1 / 2^1
        if (x >= 0xa45af1e1f40c333b3de1db4dd55f29a7) {
            res += 0x20000000000000000000000000000000;
            x = (x * FIXED_1) / 0xa45af1e1f40c333b3de1db4dd55f29a7;
        } // add 1 / 2^2
        if (x >= 0x910b022db7ae67ce76b441c27035c6a1) {
            res += 0x10000000000000000000000000000000;
            x = (x * FIXED_1) / 0x910b022db7ae67ce76b441c27035c6a1;
        } // add 1 / 2^3
        if (x >= 0x88415abbe9a76bead8d00cf112e4d4a8) {
            res += 0x08000000000000000000000000000000;
            x = (x * FIXED_1) / 0x88415abbe9a76bead8d00cf112e4d4a8;
        } // add 1 / 2^4
        if (x >= 0x84102b00893f64c705e841d5d4064bd3) {
            res += 0x04000000000000000000000000000000;
            x = (x * FIXED_1) / 0x84102b00893f64c705e841d5d4064bd3;
        } // add 1 / 2^5
        if (x >= 0x8204055aaef1c8bd5c3259f4822735a2) {
            res += 0x02000000000000000000000000000000;
            x = (x * FIXED_1) / 0x8204055aaef1c8bd5c3259f4822735a2;
        } // add 1 / 2^6
        if (x >= 0x810100ab00222d861931c15e39b44e99) {
            res += 0x01000000000000000000000000000000;
            x = (x * FIXED_1) / 0x810100ab00222d861931c15e39b44e99;
        } // add 1 / 2^7
        if (x >= 0x808040155aabbbe9451521693554f733) {
            res += 0x00800000000000000000000000000000;
            x = (x * FIXED_1) / 0x808040155aabbbe9451521693554f733;
        } // add 1 / 2^8

        z = y = x - FIXED_1;
        w = (y * y) / FIXED_1;
        res += (z * (0x100000000000000000000000000000000 - y)) / 0x100000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^01 / 01 - y^02 / 02
        res += (z * (0x0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa - y)) / 0x200000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^03 / 03 - y^04 / 04
        res += (z * (0x099999999999999999999999999999999 - y)) / 0x300000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^05 / 05 - y^06 / 06
        res += (z * (0x092492492492492492492492492492492 - y)) / 0x400000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^07 / 07 - y^08 / 08
        res += (z * (0x08e38e38e38e38e38e38e38e38e38e38e - y)) / 0x500000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^09 / 09 - y^10 / 10
        res += (z * (0x08ba2e8ba2e8ba2e8ba2e8ba2e8ba2e8b - y)) / 0x600000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^11 / 11 - y^12 / 12
        res += (z * (0x089d89d89d89d89d89d89d89d89d89d89 - y)) / 0x700000000000000000000000000000000;
        z = (z * w) / FIXED_1; // add y^13 / 13 - y^14 / 14
        res += (z * (0x088888888888888888888888888888888 - y)) / 0x800000000000000000000000000000000; // add y^15 / 15 - y^16 / 16

        return res;
    }

    /**
     * @dev computes e ^ (x / FIXED_1) * FIXED_1
     * input range: 0 <= x <= OPT_EXP_MAX_VAL - 1
     * auto-generated via 'PrintFunctionOptimalExp.py'
     * Detailed description:
     * - Rewrite the input as a sum of binary exponents and a single residual r, as small as possible
     * - The exponentiation of each binary exponent is given (pre-calculated)
     * - The exponentiation of r is calculated via Taylor series for e^x, where x = r
     * - The exponentiation of the input is calculated by multiplying the intermediate results above
     * - For example: e^5.521692859 = e^(4 + 1 + 0.5 + 0.021692859) = e^4 * e^1 * e^0.5 * e^0.021692859
     */
    function optimalExp(uint256 x) internal pure returns (uint256) {
        require(x <= OPT_EXP_MAX_VAL - 1, "MIRIN: OVERFLOW");
        uint256 res = 0;

        uint256 y;
        uint256 z;

        z = y = x % 0x10000000000000000000000000000000; // get the input modulo 2^(-3)
        z = (z * y) / FIXED_1;
        res += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
        z = (z * y) / FIXED_1;
        res += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
        z = (z * y) / FIXED_1;
        res += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
        z = (z * y) / FIXED_1;
        res += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
        z = (z * y) / FIXED_1;
        res += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
        z = (z * y) / FIXED_1;
        res += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
        z = (z * y) / FIXED_1;
        res += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
        z = (z * y) / FIXED_1;
        res += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
        z = (z * y) / FIXED_1;
        res += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
        z = (z * y) / FIXED_1;
        res += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
        z = (z * y) / FIXED_1;
        res += z * 0x000000000001c638; // add y^16 * (20! / 16!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
        z = (z * y) / FIXED_1;
        res += z * 0x000000000000017c; // add y^18 * (20! / 18!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000000000014; // add y^19 * (20! / 19!)
        z = (z * y) / FIXED_1;
        res += z * 0x0000000000000001; // add y^20 * (20! / 20!)
        res = res / 0x21c3677c82b40000 + y + FIXED_1; // divide by 20! and then add y^1 / 1! + y^0 / 0!

        if ((x & 0x010000000000000000000000000000000) != 0)
            res = (res * 0x1c3d6a24ed82218787d624d3e5eba95f9) / 0x18ebef9eac820ae8682b9793ac6d1e776; // multiply by e^2^(-3)
        if ((x & 0x020000000000000000000000000000000) != 0)
            res = (res * 0x18ebef9eac820ae8682b9793ac6d1e778) / 0x1368b2fc6f9609fe7aceb46aa619baed4; // multiply by e^2^(-2)
        if ((x & 0x040000000000000000000000000000000) != 0)
            res = (res * 0x1368b2fc6f9609fe7aceb46aa619baed5) / 0x0bc5ab1b16779be3575bd8f0520a9f21f; // multiply by e^2^(-1)
        if ((x & 0x080000000000000000000000000000000) != 0)
            res = (res * 0x0bc5ab1b16779be3575bd8f0520a9f21e) / 0x0454aaa8efe072e7f6ddbab84b40a55c9; // multiply by e^2^(+0)
        if ((x & 0x100000000000000000000000000000000) != 0)
            res = (res * 0x0454aaa8efe072e7f6ddbab84b40a55c5) / 0x00960aadc109e7a3bf4578099615711ea; // multiply by e^2^(+1)
        if ((x & 0x200000000000000000000000000000000) != 0)
            res = (res * 0x00960aadc109e7a3bf4578099615711d7) / 0x0002bf84208204f5977f9a8cf01fdce3d; // multiply by e^2^(+2)
        if ((x & 0x400000000000000000000000000000000) != 0)
            res = (res * 0x0002bf84208204f5977f9a8cf01fdc307) / 0x0000003c6ab775dd0b95b4cbee7e65d11; // multiply by e^2^(+3)

        return res;
    }

    function toInt(uint256 a) internal pure returns (uint256) {
        return a / BASE18;
    }

    function toFloor(uint256 a) internal pure returns (uint256) {
        return toInt(a) * BASE18;
    }

    function roundMul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * b;
        uint256 c1 = c0 + (BASE18 / 2);
        return c1 / BASE18;
    }

    function roundDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * BASE18;
        uint256 c1 = c0 + (b / 2);
        return c1 / b;
    }

    function power(uint256 base, uint256 exp) internal pure returns (uint256) {
        require(base >= MIN_POWER_BASE, "MIRIN: POWER_BASE_TOO_LOW");
        require(base <= MAX_POWER_BASE, "MIRIN: POWER_BASE_TOO_HIGH");

        uint256 whole = toFloor(exp);
        uint256 remain = exp - whole;

        uint256 wholePow = powInt(base, toInt(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint256 partialResult = powFrac(base, remain, POWER_PRECISION);
        return roundMul(wholePow, partialResult);
    }

    function powInt(uint256 a, uint256 n) private pure returns (uint256) {
        uint256 z = n % 2 != 0 ? a : BASE18;

        for (n /= 2; n != 0; n /= 2) {
            a = roundMul(a, a);

            if (n % 2 != 0) {
                z = roundMul(z, a);
            }
        }
        return z;
    }

    function powFrac(
        uint256 base,
        uint256 exp,
        uint256 precision
    ) private pure returns (uint256) {
        uint256 a = exp;
        (uint256 x, bool xneg) = base >= BASE18 ? (base - BASE18, false) : (BASE18 - base, true);
        uint256 term = BASE18;
        uint256 sum = term;
        bool negative = false;

        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * BASE18;
            (uint256 c, bool cneg) = a + BASE18 >= bigK ? (a + BASE18 - bigK, false) : (bigK - a - BASE18, true);
            term = roundMul(term, roundMul(c, x));
            term = roundDiv(term, bigK);
            if (term == 0) break;

            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = sum - term;
            } else {
                sum = sum + term;
            }
        }
        return sum;
    }
}

//import "hardhat/console.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @author Mudit Gupta
 */
contract PoolProxy is ERC1967Proxy {
    constructor(address _logic, bytes memory _data) payable ERC1967Proxy(_logic, _data) {}

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function upgradeTo(address newImplementation) external {
        if (msg.sender == address(this)) {
            _upgradeTo(newImplementation);
        } else {
            _fallback();
        }
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) external {
        if (msg.sender == address(this)) {
            _upgradeToAndCall(newImplementation, data, forceCall);
        } else {
            _fallback();
        }
    }
}

/**
 * @author Mudit Gupta
 */
contract PoolTemplate {
    uint256 public immutable configValue;
    address public immutable anotherConfigValue;

    constructor(bytes memory _data) {
        (configValue, anotherConfigValue) = abi.decode(_data, (uint256, address));
    }
}

/**
 * @author Mudit Gupta
 */
contract PoolFactory {
    // Consider deploying via an upgradable proxy to allow upgrading pools in the future

    function deployPoolLogic(bytes memory _deployData) external returns (address) {
        return address(new PoolTemplate(_deployData));
    }
}

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @author Mudit Gupta
 */
contract MasterDeployer is Ownable {
    event NewPoolCreated(address indexed poolAddress);

    mapping(address => bool) public whitelistedFactories;

    mapping(address => bool) public pool;

    uint256 public barFee;

    address public immutable barFeeTo;
    address public immutable bento;

    uint256 internal constant MAX_FEE = 10000; // 100%

    constructor(
        uint256 _barFee,
        address _barFeeTo,
        address _bento
    ) Ownable() {
        require(_barFee <= MAX_FEE, "INVALID_BAR_FEE");
        require(address(_barFeeTo) != address(0), "ZERO_ADDRESS");
        require(address(_bento) != address(0), "ZERO_ADDRESS");

        barFee = _barFee;
        barFeeTo = _barFeeTo;
        bento = _bento;
    }

    function deployPool(
        address _factory,
        bytes memory _deployData,
        bytes memory _initData
    ) external returns (address poolAddress) {
        require(whitelistedFactories[_factory], "Factory not whitelisted");
        address logic = PoolFactory(_factory).deployPoolLogic(_deployData);
        poolAddress = address(new PoolProxy(logic, _initData));
        pool[poolAddress] = true;
        emit NewPoolCreated(poolAddress);
    }

    function addToWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = true;
    }

    function removeFromWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = false;
    }

    function setBarFee(uint256 _barFee) external onlyOwner {
        require(_barFee <= MAX_FEE, "INVALID_BAR_FEE");
        barFee = _barFee;
    }
}

contract TridentNFT { // to-do- review 1155
    uint256 public totalSupply;
    string constant public name = "TridentNFT";
    string constant public symbol = "tNFT";
    string constant public baseURI = "PLACEHOLDER"; // WIP - make chain-based, auto-generative re: positions
    
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => Position) public positions;
    mapping(uint256 => address) public getApproved;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => string) public tokenURI;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    
    event Approval(address indexed approver, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed approver, address indexed operator, bool approved);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    struct Position {
        uint256 lower;
        uint256 upper;
        uint256 amount0;
        uint256 amount1;
        uint256 share;
        uint256 collected0;
        uint256 collected1;
    }

    function supportsInterface(bytes4 sig) external pure returns (bool) {
        return (sig == 0x80ac58cd || sig == 0x5b5e139f); // ERC-165
    }
    
    function approve(address spender, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "!owner/operator");
        getApproved[tokenId] = spender;
        emit Approval(msg.sender, spender, tokenId); 
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function _mint(
        address to, 
        uint256 lower, 
        uint256 upper, 
        uint256 amount0, 
        uint256 amount1,
        uint256 share
    ) internal returns (uint256 tokenId) { 
        totalSupply++;
        tokenId = totalSupply;
        balanceOf[to]++;
        positions[tokenId] = Position(lower, upper, amount0, amount1, share, 0, 0);
        ownerOf[tokenId] = to;
        tokenURI[tokenId] = baseURI;
        emit Transfer(address(0), to, tokenId); 
    }
    // to-do - separate out total burn, which consumes all locked value, and piecemeal 'collect'
    function _burn(uint256 tokenId) internal {
        require(msg.sender == ownerOf[tokenId], '!owner');
        totalSupply--;
        balanceOf[msg.sender]--;
        ownerOf[tokenId] = address(0);
        tokenURI[tokenId] = "";
        emit Transfer(msg.sender, address(0), tokenId); 
    }

    function transfer(address to, uint256 tokenId) external {
        require(msg.sender == ownerOf[tokenId], '!owner');
        balanceOf[msg.sender]--; 
        balanceOf[to]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = to;
        emit Transfer(msg.sender, to, tokenId); 
    }
    
    function transferFrom(address, address to, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(msg.sender == owner || msg.sender == getApproved[tokenId] || isApprovedForAll[owner][msg.sender], '!owner/spender/operator');
        balanceOf[owner]--; 
        balanceOf[to]++; 
        getApproved[tokenId] = address(0);
        ownerOf[tokenId] = to;
        emit Transfer(owner, to, tokenId); 
    }
}

// WIP - file is abstract as core functions are rationalized against IPool Trident template
abstract contract ConstantProductConcentratedPool is TridentNFT, IPool {
    event Mint(address indexed sender, uint256 tokenId, address indexed to); // reformatted for NFT - amounts can be checked via tokenId?
    event Burn(address indexed sender, uint256 tokenId, address indexed to); // reformatted for NFT - amounts can be checked via tokenId?
    event Swap( // this should not change for CPCP?
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

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
    
    uint256 public liquidity;
    int24 internal rangeSpacing; // cf.'tick' spacing
    mapping(uint256 => mapping(uint256 => LiquidityRange)) public ranges; // WIP - track liquidity by upper/lower range
    
    struct LiquidityRange {
        uint256 amount0;
        uint256 amount1;
    }

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "TRIDENT: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /// @dev
    /// Only set immutable variables here. State changes made here will not be used.
    constructor(bytes memory _deployData, address _masterDeployer) {
        (IERC20 tokenA, IERC20 tokenB, uint256 _swapFee, int24 _rangeSpacing) = abi.decode(_deployData, (IERC20, IERC20, uint256, int24));

        require(address(tokenA) != address(0), "MIRIN: ZERO_ADDRESS");
        require(address(tokenB) != address(0), "MIRIN: ZERO_ADDRESS");
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "MIRIN: INVALID_SWAP_FEE");

        (IERC20 _token0, IERC20 _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        rangeSpacing = _rangeSpacing;
        bento = IBentoBoxV1(MasterDeployer(_masterDeployer).bento());
        barFeeTo = MasterDeployer(_masterDeployer).barFeeTo();
        masterDeployer = MasterDeployer(_masterDeployer);
    }

    function init() public {
        require(totalSupply == 0);
        unlocked = 1;
    }

    function mint(uint256 lower, uint256 upper, address to) public lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        uint256 _liquidity = liquidity;
        //_mintFee(_reserve0, _reserve1, _liquidity);
        
        (uint256 balance0, uint256 balance1) = _balance();
        amount0 = balance0 - _reserve0;
        amount1 = balance1 - _reserve1;
        
        uint256 computed = MirinMath.sqrt(balance0 * balance1);
        uint256 k = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
        liquidity = ((computed - k) * _liquidity) / k;
        require(liquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        
        (uint256 rangeBalance0, uint256 rangeBalance1) = _balanceInRange(lower, upper);
        uint256 computedRange = MirinMath.sqrt(rangeBalance0 * rangeBalance1);
        uint256 kRange = MirinMath.sqrt(uint256(amount0) * amount1); 
        uint256 rangeliquidity = ((computedRange - kRange) * _liquidity) / kRange;
        require(rangeliquidity > 0, "MIRIN: INSUFFICIENT_LIQUIDITY_MINTED");
        
        uint256 share = (rangeBalance0 + amount0 / amount0) + (rangeBalance1 + amount1 / amount1);
        uint256 tokenId = _mint(to, lower, upper, amount0, amount1, share);
        _update(lower, upper, balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        ranges[lower][upper].amount0 += amount0;
        ranges[lower][upper].amount1 += amount1;
        kLast = computed;
        
        emit Mint(msg.sender, tokenId, to);
    }

    function burn(uint256 tokenId, uint256 _amount0, uint256 _amount1, address to) public lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        uint256 _liquidity = liquidity;
        //_mintFee(_reserve0, _reserve1, _liquidity);

        (uint256 balance0, uint256 balance1) = _balance();
        amount0 = (liquidity * balance0) / _liquidity;
        amount1 = (liquidity * balance1) / _liquidity;

        _burn(tokenId);

        bento.transfer(token0, address(this), to, _amount0);
        bento.transfer(token1, address(this), to, _amount1);

        balance0 -= amount0;
        balance1 -= amount1;
        
        uint256 lower = positions[tokenId].lower;
        uint256 upper = positions[tokenId].upper;
        
        ranges[lower][upper].amount0 -= _amount0;
        ranges[lower][upper].amount1 -= _amount1;
        positions[tokenId].collected0 += _amount0;
        positions[tokenId].collected1 += _amount1;
        
        _update(lower, upper, balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = MirinMath.sqrt(balance0 * balance1);
        emit Burn(msg.sender, tokenId, to);
    }
    // how can we derive range (lower/upper) params to target liquidity range internal balance mapping for transfer out?
    function swap(
        uint256 lower,
        uint256 upper,
        address tokenIn,
        address tokenOut,
        bytes calldata context,
        address recipient,
        uint256 amountIn,
        uint256 amountOut
    ) public returns (uint256) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings

        if (tokenIn == address(token0)) {
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
            require(tokenOut == address(token1), "Invalid output token");
            _swap(lower, upper, 0, amountOut, recipient, context, _reserve0, _reserve1, _blockTimestampLast);
        } else if (tokenIn == address(token1)) {
            if (amountIn > 0) amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
            require(tokenOut == address(token0), "Invalid output token");
            _swap(lower, upper, amountOut, 0, recipient, context, _reserve0, _reserve1, _blockTimestampLast);
        } else {
            require(tokenIn == address(this), "Invalid input token");
            require(tokenOut == address(token0) || tokenOut == address(token1), "Invalid output token");
            //amountOut = _burnLiquiditySingle(
            //    amountIn,
            //    amountOut,
            //    tokenOut,
            //    recipient,
            //    context,
            //    _reserve0,
            //    _reserve1,
            //    _blockTimestampLast
            //);
        }

        return amountOut;
    }

    function swap(
        uint256 lower,
        uint256 upper,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves(); // gas savings
        _swap(lower, upper, amount0Out, amount1Out, to, data, _reserve0, _reserve1, _blockTimestampLast);
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

    function _update( // is this best way to pass range params?
        uint256 lower,
        uint256 upper,
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
                uint256 price0 = (uint256(_reserve1) << PRECISION) / _reserve0; // how can we compare PRECISION and range spacing?
                price0CumulativeLast += price0 * timeElapsed;
                uint256 price1 = (uint256(_reserve0) << PRECISION) / _reserve1;
                price1CumulativeLast += price1 * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        // how can we update total and given range? this might be rationalized in feeder functions on top?
        ranges[lower][upper].amount0 = balance0;
        ranges[lower][upper].amount1 = balance1;
        
        emit Sync(uint112(balance0), uint112(balance1));
    }

    //function _mintFee(
    //    uint112 _reserve0,
    //    uint112 _reserve1,
    //    uint256 _totalSupply
    //) private returns (uint256 computed) {
    //    uint256 _kLast = kLast;
    //    if (_kLast != 0) {
    //        computed = MirinMath.sqrt(uint256(_reserve0) * _reserve1);
    //        if (computed > _kLast) {
    //            // barFee % of increase in liquidity
    //            // NB It's going to be slihgtly less than barFee % in reality due to the Math
    //            uint256 barFee = MasterDeployer(masterDeployer).barFee();
    //            uint256 liquidity = (_totalSupply * (computed - _kLast) * barFee) / computed / MAX_FEE;
    //            if (liquidity > 0) {
    //                _mint(barFeeTo, liquidity);
    //            }
    //        }
    //    }
    //}

    //function _burnLiquiditySingle(
    //    uint256 amountIn,
    //    uint256 amountOut,
    //    address tokenOut,
    //    address to,
    //    bytes calldata data,
    //    uint112 _reserve0,
    //    uint112 _reserve1,
    //    uint32 _blockTimestampLast
    //) internal returns (uint256 finalAmountOut) {
    //    uint256 _totalSupply = totalSupply;
        //_mintFee(_reserve0, _reserve1, _totalSupply);

    //    uint256 amount0;
    //    uint256 amount1;
    //    uint256 liquidity;

    //    if (amountIn > 0) {
    //       finalAmountOut = _getOutAmountForBurn(tokenOut, amountIn, _totalSupply, _reserve0, _reserve1);

    //       if (tokenOut == address(token0)) {
    //            amount0 = finalAmountOut;
    //        } else {
    //            amount1 = finalAmountOut;
    //        }

    //        _transferWithData(amount0, amount1, to, data);

    //        liquidity = balanceOf[address(this)];
    //        require(liquidity >= amountIn, "Insufficient liquidity burned");
    //    } else {
    //        if (tokenOut == address(token0)) {
    //            amount0 = amountOut;
    //        } else {
    //            amount1 = amountOut;
    //        }

    //        _transferWithData(amount0, amount1, to, data);
    //        finalAmountOut = amountOut;

    //        liquidity = balanceOf[address(this)];
    //        uint256 allowedAmountOut = _getOutAmountForBurn(tokenOut, liquidity, _totalSupply, _reserve0, _reserve1);
    //        require(finalAmountOut <= allowedAmountOut, "Insufficient liquidity burned");
    //    }

    //    _burn(address(this), liquidity);

    //    (uint256 balance0, uint256 balance1) = _balance();
    //    _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);

    //    kLast = MirinMath.sqrt(balance0 * balance1);
    //    emit Burn(msg.sender, amount0, amount1, to);
    //}

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
    
    function _balanceInRange(uint256 lower, uint256 upper) internal view returns (uint256 rangeBalance0, uint256 rangeBalance1) {
        rangeBalance0 = ranges[lower][upper].amount0;
        rangeBalance1 = ranges[lower][upper].amount1;
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
            MirinMath.sqrt(balance0Adjusted * balance1Adjusted) >=
                MirinMath.sqrt(uint256(_reserve0) * _reserve1 * MAX_FEE * MAX_FEE),
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
        uint256 lower,
        uint256 upper,
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
            //(uint256 rangeBalance0, uint256 rangeBalance1) = _balanceInRange();
            
            amount0In = balance0 + amount0Out - _reserve0;
            amount1In = balance1 + amount1Out - _reserve1;
            _compute(amount0In, amount1In, balance0, balance1, _reserve0, _reserve1);
            _update(lower, upper, balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        }
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        (uint256 balance0, uint256 balance1) = _balance();
        bento.transfer(token0, address(this), to, bento.toShare(token0, balance0 - reserve0, false));
        bento.transfer(token1, address(this), to, bento.toShare(token1, balance1 - reserve1, false));
    }

    function sync(uint256 lower, uint256 upper) external lock {
        (uint256 balance0, uint256 balance1) = _balance();
        _update(lower, upper, balance0, balance1, reserve0, reserve1, blockTimestampLast);
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

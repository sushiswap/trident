// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./pool/MirinPool.sol";

contract MirinFactory {
    uint256 public constant SUSHI_DEPOSIT = 10000;

    address public immutable SUSHI;
    address public feeTo;
    address public owner;

    mapping(address => mapping(address => address[])) public getPublicPool;
    mapping(address => mapping(address => address[])) public getFranchisedPool;
    mapping(address => bool) public isPool;
    address[] public allPools;

    event PoolCreated(
        address indexed token0,
        address indexed token1,
        bool isPublic,
        uint256 length,
        address indexed pool,
        address operator
    );
    event PoolDisabled(address indexed pool);

    constructor(
        address _sushi,
        address _feeTo,
        address _owner
    ) {
        SUSHI = _sushi;
        feeTo = _feeTo;
        owner = _owner;
    }

    function publicPoolsLength(address token0, address token1) external view returns (uint256) {
        return getPublicPool[token0][token1].length;
    }

    function franchisedPoolsLength(address token0, address token1) external view returns (uint256) {
        return getFranchisedPool[token0][token1].length;
    }

    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    function createPool(
        address tokenA,
        address tokenB,
        address curve,
        bytes32 curveData,
        address operator,
        uint8 swapFee,
        address swapFeeTo
    ) external returns (MirinPool pool) {
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "MIRIN: ZERO_ADDRESS");
        require(curve != address(0), "MIRIN: INVALID_CURVE");
        require(IMirinCurve(curve).isValidData(curveData), "MIRIN: INVALID_CURVE_DATA");
        pool = new MirinPool(token0, token1, curve, curveData, operator, swapFee, swapFeeTo);
        bool isPublic = operator == address(0);
        uint256 length;
        if (isPublic) {
            length = getPublicPool[token0][token1].length;
            getPublicPool[token0][token1].push(address(pool));
            getPublicPool[token1][token0].push(address(pool));
        } else {
            length = getFranchisedPool[token0][token1].length;
            getFranchisedPool[token0][token1].push(address(pool));
            getFranchisedPool[token1][token0].push(address(pool));
        }
        isPool[address(pool)] = true;
        allPools.push(address(pool));
        if (!isPublic) {
            IERC20(SUSHI).transferFrom(msg.sender, address(this), SUSHI_DEPOSIT);
        }
        emit PoolCreated(token0, token1, isPublic, length, address(pool), operator);
    }

    function disablePool(address to) external {
        require(isPool[msg.sender], "MIRIN: ALREADY_DISABLED");
        isPool[msg.sender] = false;

        IERC20(SUSHI).transfer(to, SUSHI_DEPOSIT);

        emit PoolDisabled(msg.sender);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == owner, "MIRIN: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner, "MIRIN: FORBIDDEN");
        owner = _owner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./pool/MirinPool.sol";

contract MirinFactory {
    uint256 public constant SUSHI_DEPOSIT = 10000;

    address public immutable SUSHI;
    address public feeTo;
    address public owner;

    mapping(address => mapping(address => address[])) public getPool;
    mapping(address => bool) public isPool;
    address[] public allPools;

    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint256 pid,
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

    function poolsLength(address token0, address token1) external view returns (uint256) {
        return getPool[token0][token1].length;
    }

    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    function createPool(
        address tokenA,
        address tokenB,
        uint8 weight0,
        uint8 weight1,
        address operator,
        uint8 swapFee,
        address swapFeeTo
    ) external returns (MirinPool pool) {
        require(tokenA != tokenB, "MIRIN: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "MIRIN: ZERO_ADDRESS");
        require(weight0 > 0 && weight1 > 0 && MirinMath.isPow2(weight0 + weight1), "MIRIN: INVALID_WEIGHTS");
        uint256 length = getPool[token0][token1].length;
        if (operator == address(0)) {
            require(length == 0, "MIRIN: MUST_BE_FIRST_POOL");
        } else {
            require(length > 0, "MIRIN: MUST_NOT_BE_FIRST_POOL");
        }

        pool = new MirinPool(token0, token1, weight0, weight1, operator, swapFee, swapFeeTo);
        getPool[token0][token1].push(address(pool));
        getPool[token1][token0].push(address(pool));
        isPool[address(pool)] = true;
        allPools.push(address(pool));

        if (operator != address(0)) {
            IERC20(SUSHI).transferFrom(msg.sender, address(this), SUSHI_DEPOSIT);
        }

        emit PoolCreated(token0, token1, length, address(pool), operator);
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

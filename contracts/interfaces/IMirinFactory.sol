// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

import "./IMirinPool.sol";

interface IMirinFactory {
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        bool isPublic,
        uint256 length,
        address indexed pool,
        address operator
    );
    event PoolDisabled(address indexed pool);

    function SUSHI_DEPOSIT() external view returns (uint256);

    function SUSHI() external view returns (address);

    function feeTo() external view returns (address);

    function owner() external view returns (address);

    function isCurveWhitelisted(address curve) external view returns (bool);

    function getPublicPool(
        address token0,
        address token1,
        uint256 index
    ) external view returns (address);

    function getFranchisedPool(
        address token0,
        address token1,
        uint256 index
    ) external view returns (address);

    function isPool(address pool) external view returns (bool);

    function allPools(uint256 index) external view returns (address);

    function publicPoolsLength(address token0, address token1) external view returns (uint256);

    function franchisedPoolsLength(address token0, address token1) external view returns (uint256);

    function allPoolsLength() external view returns (uint256);

    function whitelistCurve(address curve) external;

    function createPool(
        address tokenA,
        address tokenB,
        address curve,
        bytes32 curveData,
        address operator,
        uint8 swapFee,
        address swapFeeTo
    ) external returns (address pool);

    function disablePool(address to) external;

    function setFeeTo(address _feeTo) external;

    function setOwner(address _owner) external;
}

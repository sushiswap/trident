// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Pair.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Factory.sol";
import "../pool/ConstantProductPoolFactory.sol";
import "../deployer/MasterDeployer.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IBentoBoxMinimal.sol";
import "hardhat/console.sol";

interface IERC20 {
    function totalSupply() external returns (uint256);
}

contract Migrator {
    address public chef;
    ConstantProductPoolFactory public factory;
    IBentoBoxMinimal public bentoBox;
    uint256 public desiredLiquidity = type(uint256).max;

    constructor(
        address _chef,
        IBentoBoxMinimal _bentoBox,
        ConstantProductPoolFactory _factory
    ) {
        chef = _chef;
        bentoBox = _bentoBox;
        factory = _factory;
    }

    function migrate(IUniswapV2Pair orig) public returns (IPool) {
        require(msg.sender == chef, "!chef");

        address token0 = orig.token0();
        address token1 = orig.token1();

        bytes memory deployData = abi.encode(token0, token1, 10, false);

        IPool pair = IPool(factory.configAddress(deployData));

        if (address(pair) == (address(0))) {
            pair = IPool(factory.deployPool(deployData));
        }

        require(IERC20(address(pair)).totalSupply() == 0, "pair must have no existing supply");

        uint256 lp = orig.balanceOf(msg.sender);

        if (lp == 0) return pair;

        orig.transferFrom(msg.sender, address(orig), lp);

        desiredLiquidity = lp;

        (uint256 amount0, uint256 amount1) = orig.burn(address(bentoBox));

        bentoBox.deposit(token0, address(bentoBox), address(pair), amount0, 0);
        bentoBox.deposit(token1, address(bentoBox), address(pair), amount1, 0);

        pair.mint(abi.encode(msg.sender));

        desiredLiquidity = type(uint256).max;

        return pair;
    }
}

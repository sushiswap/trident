// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IConcentratedLiquidityPool.sol";
import "../../interfaces/ITridentRouter.sol";
import "../../interfaces/IMasterDeployer.sol";
import "./TridentNFT.sol";

/// @notice Trident Concentrated Liquidity Pool periphery contract that combines non-fungible position management and staking.
contract ConcentratedLiquidityPosition is TridentNFT {
    event Mint(address indexed pool, address indexed recipient, uint256 indexed positionId);
    event Burn(address indexed pool, address indexed owner, uint256 indexed positionId);

    address public immutable bento;
    address public immutable wETH;
    address public immutable masterDeployer;

    mapping(uint256 => Position) public positions;

    struct Position {
        IConcentratedLiquidityPool pool;
        uint128 liquidity;
        int24 lower;
        int24 upper;
        uint256 feeGrowthInside0; // @dev Per unit of liquidity.
        uint256 feeGrowthInside1;
    }

    constructor(
        address _bento,
        address _wETH,
        address _masterDeployer
    ) {
        bento = _bento;
        wETH = _wETH;
        masterDeployer = _masterDeployer;
    }

    function positionMintCallback(
        address recipient,
        int24 lower,
        int24 upper,
        uint128 amount,
        uint256 feeGrowthInside0,
        uint256 feeGrowthInside1
    ) external returns (uint256 positionId) {
        require(IMasterDeployer(masterDeployer).pools(msg.sender));
        positions[totalSupply] = Position(IConcentratedLiquidityPool(msg.sender), amount, lower, upper, feeGrowthInside0, feeGrowthInside1);
        positionId = totalSupply;
        _mint(recipient);
        emit Mint(msg.sender, recipient, positionId);
    }

    function burn(
        uint256 tokenId,
        uint128 amount,
        address recipient,
        bool unwrapBento
    ) external {
        require(msg.sender == ownerOf[tokenId], "");
        Position memory position = positions[tokenId];
        bytes memory burnData = abi.encode(position.lower, position.upper, amount, recipient, unwrapBento);
        position.pool.burn(burnData);
        if (amount < position.liquidity) {
            position.liquidity -= amount;
        } else {
            delete positions[tokenId];
            _burn(msg.sender, tokenId);
        }
        emit Burn(address(position.pool), msg.sender, tokenId);
    }

    function collect(
        uint256 tokenId,
        address recipient,
        bool unwrapBento
    ) external returns (uint256 token0amount, uint256 token1amount) {
        require(msg.sender == ownerOf[tokenId], "");
        Position storage position = positions[tokenId];
        bytes memory collectData = abi.encode(position.lower, position.upper, recipient, false);
        (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = position.pool.rangeFeeGrowth(position.lower, position.upper);
        position.pool.collect(collectData);
        token0amount = (feeGrowthInside0 - position.feeGrowthInside0) * position.liquidity;
        token1amount = (feeGrowthInside1 - position.feeGrowthInside1) * position.liquidity;
        position.feeGrowthInside0 = feeGrowthInside0;
        position.feeGrowthInside1 = feeGrowthInside1;
        _transfer(position.pool.token0(), address(this), recipient, token0amount, unwrapBento);
        _transfer(position.pool.token1(), address(this), recipient, token1amount, unwrapBento);
    }

    function _depositToBentoBox(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (token == wETH && address(this).balance != 0) {
            // @dev toAmount(address,uint256,bool).
            (, bytes memory _underlyingAmount) = bento.call(abi.encodeWithSelector(0x56623118, wETH, amount, true));
            uint256 underlyingAmount = abi.decode(_underlyingAmount, (uint256));
            if (address(this).balance > underlyingAmount) {
                // @dev Deposit ETH into `recipient` `bento` account -
                // deposit(address,address,address,uint256,uint256).
                (bool ethDepositSuccess, ) = bento.call{value: underlyingAmount}(
                    abi.encodeWithSelector(0x02b9446c, token, msg.sender, recipient, amount)
                );
                require(ethDepositSuccess, "ETH_DEPOSIT_FAILED");
                return;
            }
        }
        // @dev Deposit ERC-20 token into `recipient` `bento` account
        // - deposit(address,address,address,uint256,uint256).
        (bool depositSuccess, ) = bento.call(abi.encodeWithSelector(0x02b9446c, token, msg.sender, recipient, amount));
        require(depositSuccess, "DEPOSIT_FAILED");
    }

    function _transfer(
        address token,
        address from,
        address to,
        uint256 shares,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            // @dev withdraw(address,address,address,uint256,uint256).
            (bool withdrawSuccess, ) = bento.call(abi.encodeWithSelector(0x97da6d30, token, from, to, 0, shares));
            require(withdrawSuccess, "WITHDRAW_FAILED");
        } else {
            // @dev transfer(address,address,address,uint256).
            (bool transferSuccess, ) = bento.call(abi.encodeWithSelector(0xf18d03cc, token, from, to, shares));
            require(transferSuccess, "TRANSFER_FAILED");
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IConcentratedLiquidityPool.sol";
import "../../interfaces/ITridentRouter.sol";
import "./TridentNFT.sol";

/// @notice Trident Concentrated Liquidity Pool periphery contract that combines non-fungible position management and staking.
contract ConcentratedLiquidityPosition is TridentNFT {
    event Mint(IConcentratedLiquidityPool indexed pool, bytes mintData);
    event Burn(IConcentratedLiquidityPool indexed pool, bytes burnData, uint256 indexed tokenId);

    struct Position {
        IConcentratedLiquidityPool pool;
        uint128 liquidity;
        int24 lower;
        int24 upper;
        uint256 feeGrowthInside0; // @dev Per unit of liquidity.
        uint256 feeGrowthInside1;
    }

    mapping(uint256 => Position) public positions;

    address public immutable bento;
    address public immutable wETH;

    constructor(address _bento, address _wETH) {
        bento = _bento;
        wETH = _wETH;
    }

    function mint(
        ITridentRouter.TokenInput[] memory tokenInput,
        IConcentratedLiquidityPool pool,
        bytes memory mintData
    ) external {
        (, int24 lower, , int24 upper, uint128 amount, address recipient) = abi.decode(
            mintData,
            (int24, int24, int24, int24, uint128, address)
        );
        for (uint256 i; i < tokenInput.length; i++) {
            if (tokenInput[i].native) {
                _depositToBentoBox(tokenInput[i].token, address(pool), tokenInput[i].amount);
            } else {
                _transfer(tokenInput[i].token, msg.sender, address(pool), tokenInput[i].amount, false);
            }
        }
        pool.mint(mintData);
        (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = pool.rangeFeeGrowth(lower, upper);
        positions[totalSupply] = Position(IConcentratedLiquidityPool(pool), amount, lower, upper, feeGrowthInside0, feeGrowthInside1);
        // @dev Mint Position 'NFT'.
        _mint(recipient);
        emit Mint(pool, mintData);
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
            _burn(tokenId);
        }
        emit Burn(position.pool, burnData, tokenId);
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
                (bool success0, ) = bento.call{value: underlyingAmount}(
                    abi.encodeWithSelector(0x02b9446c, token, msg.sender, recipient, amount)
                );
                require(success0, "DEPOSIT_FAILED");
                return;
            }
        }
        // @dev Deposit ERC-20 token into `recipient` `bento` account
        // - deposit(address,address,address,uint256,uint256).
        (bool success1, ) = bento.call(abi.encodeWithSelector(0x02b9446c, token, msg.sender, recipient, amount));
        require(success1, "DEPOSIT_FAILED");
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
            (bool success, ) = bento.call(abi.encodeWithSelector(0x97da6d30, token, from, to, 0, shares));
            require(success, "WITHDRAW_FAILED");
        } else {
            // @dev transfer(address,address,address,uint256).
            (bool success, ) = bento.call(abi.encodeWithSelector(0xf18d03cc, token, from, to, shares));
            require(success, "TRANSFER_FAILED");
        }
    }
}

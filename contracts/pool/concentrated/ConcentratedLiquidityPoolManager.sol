// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../interfaces/IConcentratedLiquidityPool.sol";
import "../../interfaces/IPool.sol";
import "./TridentNFT.sol";

/// @notice Trident Concentrated Liquidity Pool periphery contract that combines non-fungible position management and staking.
contract ConcentratedLiquidityPoolManager is TridentNFT {
    event AddIncentive(IConcentratedLiquidityPool indexed pool, Incentive indexed incentive);
    event ReclaimIncentive(IConcentratedLiquidityPool indexed pool, uint256 indexed incentiveId);
    event Subscribe(uint256 indexed positionId, uint256 indexed incentiveId);
    event ClaimReward(uint256 indexed positionId, uint256 indexed incentiveId, address indexed recipient);
    event Mint(address indexed pool, bytes mintData);
    event Burn(IPool indexed pool, bytes burnData, uint256 indexed tokenId);

    struct Position {
        IConcentratedLiquidityPool pool;
        uint128 liquidity;
        int24 lower;
        int24 upper;
    }

    struct Incentive {
        address owner;
        address token;
        uint256 rewardsUnclaimed;
        uint160 secondsClaimed; // @dev x128.
        uint32 startTime;
        uint32 endTime;
        uint32 expiry;
    }

    struct Stake {
        uint160 secondsInsideLast; // @dev x128.
        bool initialized;
    }
    /// @dev `ITridentRouter`.
    struct TokenInput {
        address token;
        bool native;
        uint256 amount;
    }

    mapping(IConcentratedLiquidityPool => uint256) public incentiveCount;
    mapping(IConcentratedLiquidityPool => mapping(uint256 => Incentive)) public incentives;
    mapping(uint256 => Position) public positions;
    mapping(uint256 => mapping(uint256 => Stake)) public stakes;

    address public immutable bento;
    address public immutable wETH;

    constructor(address _bento, address _wETH) {
        bento = _bento;
        wETH = _wETH;
    }

    function addIncentive(IConcentratedLiquidityPool pool, Incentive memory incentive) public {
        uint32 current = uint32(block.timestamp);
        require(current <= incentive.startTime, "ALREADY_STARTED");
        require(current <= incentive.endTime, "ALREADY_ENDED");
        require(incentive.startTime < incentive.endTime, "START_PAST_END");
        require(incentive.endTime + 5 weeks < incentive.expiry, "END_PAST_BUFFER");
        require(incentive.rewardsUnclaimed != 0, "NO_REWARDS");
        incentives[pool][incentiveCount[pool]++] = incentive;
        _transfer(incentive.token, msg.sender, address(this), incentive.rewardsUnclaimed, false);
        emit AddIncentive(pool, incentive);
    }

    /// @dev Withdraws any unclaimed incentive rewards.
    function reclaimIncentive(
        IConcentratedLiquidityPool pool,
        uint256 incentiveId,
        uint256 amount,
        address receiver,
        bool unwrapBento
    ) public {
        Incentive storage incentive = incentives[pool][incentiveId];
        require(incentive.owner == msg.sender, "NOT_OWNER");
        require(incentive.expiry < block.timestamp, "EXPIRED");
        require(incentive.rewardsUnclaimed >= amount, "ALREADY_CLAIMED");
        _transfer(incentive.token, address(this), receiver, amount, unwrapBento);
        emit ReclaimIncentive(pool, incentiveId);
    }

    /// @dev Subscribes a non-fungible position token to an incentive.
    function subscribe(uint256 positionId, uint256 incentiveId) public {
        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        Incentive memory incentive = incentives[pool][positionId];
        Stake storage stake = stakes[positionId][incentiveId];
        require(position.liquidity != 0, "INACTIVE");
        require(stake.secondsInsideLast == 0, "SUBSCRIBED");
        require(incentiveId <= incentiveCount[pool], "NOT_INCENTIVE");
        require(block.timestamp > incentive.startTime && block.timestamp < incentive.endTime, "TIMED_OUT");
        stakes[positionId][incentiveId] = Stake(uint160(pool.rangeSecondsInside(position.lower, position.upper)), true);
        emit Subscribe(positionId, incentiveId);
    }

    function claimReward(
        uint256 positionId,
        uint256 incentiveId,
        address recipient,
        bool unwrapBento
    ) public {
        require(ownerOf[positionId] == msg.sender, "OWNER");
        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        Incentive storage incentive = incentives[position.pool][positionId];
        Stake storage stake = stakes[positionId][incentiveId];
        require(stake.initialized, "UNINITIALIZED");
        uint256 secondsPerLiquidityInside = pool.rangeSecondsInside(position.lower, position.upper) - stake.secondsInsideLast;
        uint256 secondsInside = secondsPerLiquidityInside * position.liquidity;
        uint256 maxTime = incentive.endTime < block.timestamp ? block.timestamp : incentive.endTime;
        uint256 secondsUnclaimed = (maxTime - incentive.startTime) << (128 - incentive.secondsClaimed);
        uint256 rewards = (incentive.rewardsUnclaimed * secondsInside) / secondsUnclaimed;
        incentive.rewardsUnclaimed -= rewards;
        incentive.secondsClaimed += uint160(secondsInside);
        stake.secondsInsideLast += uint160(secondsPerLiquidityInside);
        _transfer(incentive.token, address(this), recipient, rewards, unwrapBento);
        emit ClaimReward(positionId, incentiveId, recipient);
    }

    function getReward(uint256 positionId, uint256 incentiveId) public view returns (uint256 rewards, uint256 secondsInside) {
        Position memory position = positions[positionId];
        IConcentratedLiquidityPool pool = position.pool;
        Incentive memory incentive = incentives[pool][positionId];
        Stake memory stake = stakes[positionId][incentiveId];
        if (stake.initialized) {
            secondsInside = (pool.rangeSecondsInside(position.lower, position.upper) - stake.secondsInsideLast) * position.liquidity;
            uint256 maxTime = incentive.endTime < block.timestamp ? block.timestamp : incentive.endTime;
            uint256 secondsUnclaimed = (maxTime - incentive.startTime) << (128 - incentive.secondsClaimed);
            rewards = (incentive.rewardsUnclaimed * secondsInside) / secondsUnclaimed;
        }
    }

    function mint(TokenInput[] memory tokenInput, address pool, bytes memory mintData) public {
        (, int24 lower, , int24 upper, uint128 amount, address recipient) = abi.decode(
            mintData,
            (int24, int24, int24, int24, uint128, address)
        );
        for (uint256 i; i < tokenInput.length; i++) {
            if (tokenInput[i].native) {
                _depositToBentoBox(tokenInput[i].token, pool, tokenInput[i].amount);
            } else {
                _transfer(tokenInput[i].token, msg.sender, pool, tokenInput[i].amount, false);
            }
        }
        IPool(pool).mint(mintData);
        positions[totalSupply] = Position(IConcentratedLiquidityPool(pool), amount, lower, upper);
        // @dev Mint Position 'NFT'.
        _mint(recipient);
        emit Mint(pool, mintData);
    }
    
    function burn(
        IPool pool,
        bytes memory burnData,
        uint256 tokenId
    ) public {
        pool.burn(burnData);
        // @dev Burn Position 'NFT'.
        _burn(tokenId);
        emit Burn(pool, burnData, tokenId);
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
                (bool success0, ) = bento.call{value: underlyingAmount}(abi.encodeWithSelector(0x02b9446c, token, msg.sender, recipient, amount));
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

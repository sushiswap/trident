// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

// @notice Trident pool migrator contract for legacy SushiSwap.
contract Migrator {
    address public immutable bento;
    address public immutable masterChef;
    address public immutable masterDeployer;
    address public immutable pairPoolDeployer;
    address public immutable wETH;
    uint256 public desiredLiquidity;

    constructor(
        address _bento,
        address _masterChef,
        address _masterDeployer,
        address _pairPoolDeployer,
        address _wETH
    ) {
        bento = _bento;
        masterChef = _masterChef;
        masterDeployer = _masterDeployer;
        pairPoolDeployer = _pairPoolDeployer;
        wETH = _wETH;
        desiredLiquidity = type(uint256).max;
    }
    
    function migrate(address origin, address destination, address factory) public returns (address pair) {
        require(msg.sender == masterChef, "NOT_CHEF");
        // @dev Get the `origin` pair.
        (, bytes memory _token0) = origin.staticcall(abi.encodeWithSelector(0x0dfe1681)); // @dev token0().
        (, bytes memory _token1) = origin.staticcall(abi.encodeWithSelector(0xd21220a7)); // @dev token1().
        address token0 = abi.decode(_token0, (address));
        address token1 = abi.decode(_token1, (address));
        { // @dev Scope configuration and deployment checks.
            // @dev Get rest of configuration from `destination`.
            (, bytes memory _swapFee) = destination.staticcall(abi.encodeWithSelector(0x54cf2aeb)); // @dev swapFee().
            (, bytes memory _twapSupport) = destination.staticcall(abi.encodeWithSelector(0xec44ff8e)); // @dev twapSupport().
            uint256 swapFee = abi.decode(_swapFee, (uint256));
            bool twapSupport = abi.decode(_twapSupport, (bool));
            // @dev Confirm pair configuration.
            bytes memory deployData = abi.encode(token0, token1, swapFee, twapSupport);
            (, bytes memory _pair) = pairPoolDeployer.staticcall(abi.encodeWithSelector(0x0d617dfa, deployData)); // @dev configAddress(bytes).
            pair = abi.decode(_pair, (address));
            require(pair == destination, "NOT_DESTINATION");
            // @dev If `destination` is uninitialized, deploy.
            if (pair == address(0)) {
                (bool deploySuccess, bytes memory _newPair) = masterDeployer.call(abi.encodeWithSelector(0x250558dc, factory, deployData)); // @dev deployPool(address,bytes).
                require(deploySuccess, "DEPLOY_FAILED");
                pair = abi.decode(_newPair, (address));
            }
        }
        // @dev Check `destination` LP has not already initialized.
        (, bytes memory _totalSupply) = origin.staticcall(abi.encodeWithSelector(0x18160ddd)); // @dev totalSupply().
        uint256 totalSupply = abi.decode(_totalSupply, (uint256));
        require(totalSupply == 0, "PAIR_ALREADY_INITIALIZED");
        // @dev Get `origin` LP balance from `MasterChef`.
        uint256 lp = _balanceOf(origin, msg.sender);
        if (lp == 0) return pair;
        // @dev Forward `origin` LP balance from `MasterChef` to `origin` for burn.
        (bool transferFromSuccess, bytes memory transferFromData) = origin.call(abi.encodeWithSelector(0x23b872dd, msg.sender, origin, lp)); // @dev transferFrom(address,address,uint256).
        require(transferFromSuccess && (transferFromData.length == 0 || abi.decode(transferFromData, (bool))), "TRANSFER_FROM_FAILED");
        // @dev Complete LP migration with burn from `origin` and mint into `destination` pair.
        desiredLiquidity = lp;
        (bool burnSuccess, bytes memory burnData) = origin.call(abi.encodeWithSelector(0x89afcb44, bento)); // @dev burn(address).
        require(burnSuccess, "BURN_FAILED");
        (uint256 amount0, uint256 amount1) = abi.decode(burnData, (uint256, uint256));
        _depositToBentoBox(token0, pair, amount0);
        _depositToBentoBox(token1, pair, amount1);
        (bool mintSuccess, ) = pair.call(abi.encodeWithSelector(0x7ba0e2e7, abi.encode(msg.sender))); // @dev mint(bytes).
        require(mintSuccess, "MINT_FAILED");
        desiredLiquidity = type(uint256).max;
        return pair;
    }
    
    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool balanceSuccess, bytes memory balanceData) = token.staticcall(abi.encodeWithSelector(0x70a08231, account)); // @dev balanceOf(address).
        require(balanceSuccess && balanceData.length >= 32, "BALANCE_OF_FAILED");
        balance = abi.decode(balanceData, (uint256));
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
                (bool ethDepositSuccess, ) = bento.call{value: underlyingAmount}(abi.encodeWithSelector(0x02b9446c, token, msg.sender, recipient, amount));
                require(ethDepositSuccess, "ETH_DEPOSIT_FAILED");
                return;
            }
        }
        // @dev Deposit ERC-20 token into `recipient` `bento` account
        // - deposit(address,address,address,uint256,uint256).
        (bool depositSuccess, ) = bento.call(abi.encodeWithSelector(0x02b9446c, token, msg.sender, recipient, amount));
        require(depositSuccess, "DEPOSIT_FAILED");
    }
}

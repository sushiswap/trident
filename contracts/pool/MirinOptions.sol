// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinOracle.sol";
import "./MirinLoanContracts.sol";
import "./MirinOptionContracts.sol";

/**
 * @dev Originally DeriswapV1Pair
 * @author Andre Cronje, LevX
 */
contract MirinOptions is MirinOracle {
    using FixedPoint for *;
    using SafeERC20 for IERC20;

    /// @notice The create option event
    event OptionCreated(
        uint256 id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 strike,
        uint256 created,
        uint256 expire
    );

    /// @notice swap the position event when processing options
    event OptionExercised(
        uint256 id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 strike,
        uint256 excercised,
        uint256 expire
    );

    struct Option {
        address asset;
        uint256 amount;
        uint256 strike;
        uint256 expire;
        uint256 optionType;
    }

    struct OptionInternal {
        address asset; // 20 bytes
        uint48 expire; // 5 bytes
        uint8 call; // 1 byte
        uint256 amount;
        uint256 strike;
    }

    MirinLoanContracts public immutable loanContracts;
    MirinOptionContracts public immutable optionContracts;
    OptionInternal[] private _options;

    constructor(
        address _token0,
        address _token1,
        uint8 _weight0,
        uint8 _weight1
    ) MirinOracle(_token0, _token1, _weight0, _weight1) {
        loanContracts = new MirinLoanContracts();
        optionContracts = new MirinOptionContracts();
    }

    uint256 private _calls0;
    uint256 private _calls1;

    uint256 private _puts0;
    uint256 private _puts1;

    function quoteOption(address tokenIn, uint256 t) public view returns (uint256 call, uint256 put) {
        uint256 price = price(tokenIn);
        return quoteOptionPrice(tokenIn, t, price, price);
    }

    function quoteOptionPrice(
        address tokenIn,
        uint256 t,
        uint256 sp,
        uint256 st
    ) public view returns (uint256 call, uint256 put) {
        uint256 v = realizedVolatility(tokenIn, t, 48);
        return MirinMath.quoteOptionAll(t, v, sp, st);
    }

    function options(uint256 _id) external view returns (Option memory _option) {
        OptionInternal memory _ostore = _options[_id];
        _option.asset = _ostore.asset;
        _option.amount = _ostore.amount;
        _option.strike = _ostore.strike;
        _option.expire = uint256(_ostore.expire);
        _option.optionType = uint256(_ostore.call);
    }

    function optionsLength() external view returns (uint256) {
        return _options.length;
    }

    function _unpackOption(OptionInternal memory stored) private pure returns (Option memory _option) {
        _option.asset = stored.asset;
        _option.amount = stored.amount;
        _option.strike = stored.strike;
        _option.expire = uint256(stored.expire);
        _option.optionType = uint256(stored.call);
    }

    function _period(uint256 t) private pure returns (uint256) {
        return t * 1 days;
    }

    function feeDetail(
        address token,
        uint256 st,
        uint256 t,
        uint256 optionType
    )
        external
        view
        returns (
            uint256 _call,
            uint256 _put,
            uint256 _fee
        )
    {
        (_call, _put) = quoteOptionPrice(token, t, price(token), st);
        _fee = optionType == 0 ? _call : _put;
        return (_call, _put, _fee);
    }

    function fee(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 optionType
    ) public view returns (uint256) {
        (uint256 _call, uint256 _put) = quoteOptionPrice(token, t, price(token), st);
        uint256 _fee = optionType == 0 ? _call : _put;
        return utilization(token, optionType, (_fee * amount) / (uint256(10)**IERC20(token).decimals()));
    }

    function callATM(
        address token,
        uint256 amount,
        uint256 t,
        uint256 maxFee
    ) external {
        createOption(token, amount, price(token), t, 0, maxFee);
    }

    function putATM(
        address token,
        uint256 amount,
        uint256 t,
        uint256 maxFee
    ) external {
        createOption(token, amount, price(token), t, 1, maxFee);
    }

    function createCall(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 maxFee
    ) external {
        createOption(token, amount, st, t, 0, maxFee);
    }

    function createPut(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 maxFee
    ) external {
        createOption(token, amount, st, t, 1, maxFee);
    }

    function utilization(
        address token,
        uint256 optionType,
        uint256 amount
    ) public view returns (uint256) {
        if (token == token0) {
            if (_calls0 == 0 || _puts0 == 0) return amount;
            if (optionType == 0) return (amount * _calls0) / _puts0;
            else return (amount * _puts0) / _calls0;
        } else {
            if (_calls1 == 0 || _puts1 == 0) return amount;
            if (optionType == 0) return (amount * _calls1) / _puts1;
            else return (amount * _puts1) / _calls1;
        }
    }

    function createOption(
        address token,
        uint256 amount,
        uint256 st,
        uint256 t,
        uint256 optionType,
        uint256 maxFee
    ) public {
        address _t0 = token0;
        optionType == 0
            ? (_t0 == token ? _calls0 = _calls0 + amount : _calls1 = _calls1 + amount)
            : (_t0 == token ? _puts0 = _puts0 + amount : _puts1 = _puts1 + amount);
        uint256 _fee = fee(token, amount, st, t, optionType);
        require(_fee <= maxFee, "MIRIN: FEE_TOO_HIGH");
        IERC20(_t0 == token ? token1 : _t0).safeTransferFrom(msg.sender, address(this), _fee);
        emit OptionCreated(
            _options.length,
            msg.sender,
            token,
            amount,
            st,
            block.timestamp,
            block.timestamp + _period(t)
        );
        optionContracts.mint(msg.sender, _options.length);
        _options.push(OptionInternal(token, uint48(block.timestamp + _period(t)), uint8(optionType), amount, st));
    }

    function exerciseOptionProfitOnly(uint256 id) external {
        require(optionContracts.isApprovedOrOwner(msg.sender, id), "MIRIN: FORBIDDEN");
        OptionInternal storage _pos = _options[id];
        Option memory _o = _unpackOption(_pos);
        require(_o.expire > block.timestamp, "MIRIN: EXPIRED");
        _pos.expire = uint48(block.timestamp);

        uint256 _sp = price(_o.asset);

        uint256 profit;
        if (_o.optionType == 0) {
            require(_o.strike <= _sp, "MIRIN: CURRENT_PRICE_TOO_LOW");
            profit = (_sp - _o.strike) * _o.amount;
        } else if (_o.optionType == 1) {
            require(_o.strike >= _sp, "MIRIN: CURRENT_PRICE_TOO_HIGH");
            profit = (_o.strike - _sp) * _o.amount;
        }
        IERC20(token0 == _o.asset ? token1 : token0).transfer(msg.sender, profit);

        emit OptionExercised(id, msg.sender, _o.asset, _o.amount, _o.strike, block.timestamp, _o.expire);
    }

    function excerciseOption(uint256 id) external {
        require(optionContracts.isApprovedOrOwner(msg.sender, id), "MIRIN: FORBIDDEN");
        OptionInternal storage _pos = _options[id];
        Option memory _o = _unpackOption(_pos);
        require(_o.expire > block.timestamp, "MIRIN: EXPIRED");
        _pos.expire = uint48(block.timestamp);

        uint256 _sp = price(_o.asset);

        if (_o.optionType == 0) {
            // call asset
            require(_o.strike <= _sp, "MIRIN: CURRENT_PRICE_TOO_LOW");
            IERC20(token0 == _o.asset ? token1 : token0).safeTransferFrom(
                msg.sender,
                address(this),
                (_o.strike * _o.amount) / IERC20(_o.asset).decimals()
            );
            IERC20(_o.asset).safeTransfer(msg.sender, _o.amount);
        } else if (_o.optionType == 1) {
            // put asset
            require(_o.strike >= _sp, "MIRIN: CURRENT_PRICE_TOO_HIGH");
            IERC20(_o.asset).safeTransferFrom(msg.sender, address(this), _o.amount);
            IERC20(token0 == _o.asset ? token1 : token0).safeTransfer(
                msg.sender,
                (_o.strike * _o.amount) / (IERC20(_o.asset).decimals())
            );
        }
        emit OptionExercised(id, msg.sender, _o.asset, _o.amount, _o.strike, block.timestamp, _o.expire);
    }
}

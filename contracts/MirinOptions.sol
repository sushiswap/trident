// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "./MirinERC20.sol";
import "./MirinLoanContracts.sol";
import "./MirinOptionContracts.sol";

/**
 * @dev Originally DeriswapV1Pair
 * @author Andre Cronje, LevX
 */
contract MirinOptions is MirinERC20 {
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;

    MirinLoanContracts public immutable loansnft;
    MirinOptionContracts public immutable optionsnft;

    constructor(
        address _token0,
        address _token1,
        address _operator,
        uint8 _swapFee,
        address _swapFeeTo
    ) MirinERC20(_token0, _token1, _operator, _swapFee, _swapFeeTo) {
        loansnft = new MirinLoanContracts();
        optionsnft = new MirinOptionContracts();
    }

    /// @notice The create option event
    event Created(
        uint256 id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 strike,
        uint256 created,
        uint256 expire
    );

    /// @notice swap the position event when processing options
    event Exercised(
        uint256 id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 strike,
        uint256 excercised,
        uint256 expire
    );

    uint256 private calls0;
    uint256 private calls1;

    uint256 private puts0;
    uint256 private puts1;

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

    struct ostore {
        address asset; // 20 bytes
        uint48 expire; // 5 bytes
        uint8 call; // 1 byte
        uint256 amount;
        uint256 strike;
    }

    function options(uint256 _id) public view returns (opt memory _option) {
        ostore memory _ostore = ostores[_id];
        _option.asset = _ostore.asset;
        _option.amount = _ostore.amount;
        _option.strike = _ostore.strike;
        _option.expire = uint256(_ostore.expire);
        _option.optionType = uint256(_ostore.call);
    }

    function store2opt(ostore memory _ostore) public pure returns (opt memory _option) {
        _option.asset = _ostore.asset;
        _option.amount = _ostore.amount;
        _option.strike = _ostore.strike;
        _option.expire = uint256(_ostore.expire);
        _option.optionType = uint256(_ostore.call);
    }

    struct opt {
        address asset;
        uint256 amount;
        uint256 strike;
        uint256 expire;
        uint256 optionType;
    }

    ostore[] public ostores;

    function count() public view returns (uint256) {
        return ostores.length;
    }

    function option(uint256 _id)
        external
        view
        returns (
            address asset,
            uint256 amount,
            uint256 strike,
            uint256 expire,
            uint256 optionType
        )
    {
        opt memory _o = options(_id);
        return (_o.asset, _o.amount, _o.strike, _o.expire, _o.optionType);
    }

    function period(uint256 t) public pure returns (uint256) {
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
        if (token == TOKEN0) {
            if (calls0 == 0 || puts0 == 0) return amount;
            if (optionType == 0) return (amount * calls0) / puts0;
            else return (amount * puts0) / calls0;
        } else {
            if (calls1 == 0 || puts1 == 0) return amount;
            if (optionType == 0) return (amount * calls1) / puts1;
            else return (amount * puts1) / calls1;
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
        address _t0 = TOKEN0;
        optionType == 0
            ? (_t0 == token ? calls0 = calls0 + amount : calls1 = calls1 + amount)
            : (_t0 == token ? puts0 = puts0 + amount : puts1 = puts1 + amount);
        uint256 _fee = fee(token, amount, st, t, optionType);
        require(_fee <= maxFee, "maxFee");
        IERC20(_t0 == token ? TOKEN1 : _t0).safeTransferFrom(msg.sender, address(this), _fee);
        emit Created(ostores.length, msg.sender, token, amount, st, block.timestamp, block.timestamp + period(t));
        optionsnft.mint(msg.sender, ostores.length);
        ostores.push(ostore(token, uint48(block.timestamp + period(t)), uint8(optionType), amount, st));
    }

    function exerciseOptionProfitOnly(uint256 id) external {
        require(optionsnft.isApprovedOrOwner(msg.sender, id));
        ostore storage _pos = ostores[id];
        opt memory _o = store2opt(_pos);
        require(_o.expire > block.timestamp);
        _pos.expire = uint48(block.timestamp);

        uint256 _sp = price(_o.asset);

        uint256 profit;
        if (_o.optionType == 0) {
            require(_o.strike <= _sp, "Current price is too low");
            profit = (_sp - _o.strike) * _o.amount;
        } else if (_o.optionType == 1) {
            require(_o.strike >= _sp, "Current price is too high");
            profit = (_o.strike - _sp) * _o.amount;
        }
        IERC20(TOKEN0 == _o.asset ? TOKEN1 : TOKEN0).transfer(msg.sender, profit);

        emit Exercised(id, msg.sender, _o.asset, _o.amount, _o.strike, block.timestamp, _o.expire);
    }

    function excerciseOption(uint256 id) external {
        require(optionsnft.isApprovedOrOwner(msg.sender, id));
        ostore storage _pos = ostores[id];
        opt memory _o = store2opt(_pos);
        require(_o.expire > block.timestamp);
        _pos.expire = uint48(block.timestamp);

        uint256 _sp = price(_o.asset);

        if (_o.optionType == 0) {
            // call asset
            require(_o.strike <= _sp, "Current price is too low");
            IERC20(TOKEN0 == _o.asset ? TOKEN1 : TOKEN0).safeTransferFrom(
                msg.sender,
                address(this),
                (_o.strike * _o.amount) / IERC20(_o.asset).decimals()
            );
            IERC20(_o.asset).safeTransfer(msg.sender, _o.amount);
        } else if (_o.optionType == 1) {
            // put asset
            require(_o.strike >= _sp, "Current price is too high");
            IERC20(_o.asset).safeTransferFrom(msg.sender, address(this), _o.amount);
            IERC20(TOKEN0 == _o.asset ? TOKEN1 : TOKEN0).safeTransfer(
                msg.sender,
                (_o.strike * _o.amount) / (IERC20(_o.asset).decimals())
            );
        }
        emit Exercised(id, msg.sender, _o.asset, _o.amount, _o.strike, block.timestamp, _o.expire);
    }
}

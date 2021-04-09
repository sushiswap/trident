// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../libraries/Strings.sol";
import "../libraries/Address.sol";
import "../libraries/UQ112x112.sol";
import "../libraries/FixedPoint.sol";
import "../libraries/SafeERC20.sol";
import "../libraries/EnumerableMap.sol";
import "../libraries/EnumerableSet.sol";
import "../libraries/MathUtils.sol";

import "hardhat/console.sol";

contract LibraryTest {
    using Strings for uint256;
    using Address for address;
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using MathUtils for uint256;

    receive() external payable {}

    // Strings
    function uintToString(uint256 value) public pure returns (string memory) {
        return Strings.toString(value);
    }

    // Address
    function isContract(address account) public view returns (bool) {
        return Address.isContract(account);
    }

    function sendValue(address payable recipient, uint256 amount) public {
        Address.sendValue(recipient, amount);
    }

    function functionCall1(address target, bytes memory data) public returns (bytes memory) {
        return Address.functionCall(target, data);
    }

    function functionCall2(
        address target,
        bytes memory data,
        string memory errorMessage
    ) public returns (bytes memory) {
        return Address.functionCall(target, data, errorMessage);
    }

    function functionCallWithValue1(
        address target,
        bytes memory data,
        uint256 value
    ) public returns (bytes memory) {
        return Address.functionCallWithValue(target, data, value);
    }

    function functionCallWithValue2(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) public returns (bytes memory) {
        return Address.functionCallWithValue(target, data, value, errorMessage);
    }

    function returnCallData(string memory signature, bytes memory data) public pure returns (bytes memory) {
        return abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
    }

    // UQ112x112
    function encode(uint112 y) public pure returns (uint224) {
        return UQ112x112.encode(y);
    }

    function uqdiv(uint224 x, uint112 y) public pure returns (uint224) {
        return UQ112x112.uqdiv(x, y);
    }

    // FixedPoint
    function encodeFP(uint112 x) public pure returns (FixedPoint.uq112x112 memory) {
        return FixedPoint.encode(x);
    }

    function encode144(uint144 x) public pure returns (FixedPoint.uq144x112 memory) {
        return FixedPoint.encode144(x);
    }

    function div224By112(FixedPoint.uq112x112 memory self, uint112 x)
        public
        pure
        returns (FixedPoint.uq112x112 memory)
    {
        return FixedPoint.div(self, x);
    }

    function mul224To256(FixedPoint.uq112x112 memory self, uint256 y)
        public
        pure
        returns (FixedPoint.uq144x112 memory)
    {
        return FixedPoint.mul(self, y);
    }

    function div256By112(FixedPoint.uq144x112 memory self, uint112 x)
        public
        pure
        returns (FixedPoint.uq144x112 memory)
    {
        return FixedPoint.div(self, x);
    }

    function mul256To256(FixedPoint.uq144x112 memory self, uint256 y)
        public
        pure
        returns (FixedPoint.uq144x112 memory)
    {
        return FixedPoint.mul(self, y);
    }

    function fraction(uint112 numerator, uint112 denominator) public pure returns (FixedPoint.uq112x112 memory) {
        return FixedPoint.fraction(numerator, denominator);
    }

    function decode(FixedPoint.uq112x112 memory self) public pure returns (uint112) {
        return FixedPoint.decode(self);
    }

    function decode144(FixedPoint.uq144x112 memory self) public pure returns (uint144) {
        return FixedPoint.decode144(self);
    }

    // SafeERC20
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) public {
        SafeERC20.safeTransfer(token, to, value);
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) public {
        SafeERC20.safeTransferFrom(token, from, to, value);
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) public {
        SafeERC20.safeApprove(token, spender, value);
    }

    // EnumerableMap
    EnumerableMap.UintToAddressMap private tokenOwners;

    function set(uint256 key, address value) public returns (bool) {
        return tokenOwners.set(key, value);
    }

    function remove(uint256 key) public returns (bool) {
        return tokenOwners.remove(key);
    }

    function contains(uint256 key) public view returns (bool) {
        return tokenOwners.contains(key);
    }

    function length() public view returns (uint256) {
        return tokenOwners.length();
    }

    function at(uint256 index) public view returns (uint256, address) {
        (uint256 key, address value) = tokenOwners.at(index);
        return (key, value);
    }

    function get(uint256 key) public view returns (address) {
        return tokenOwners.get(key);
    }

    function get(uint256 key, string memory errorMessage) public view returns (address) {
        return tokenOwners.get(key, errorMessage);
    }

    // EnumerableSet
    mapping(address => EnumerableSet.UintSet) private myTokens;

    function addSetUint(uint256 value) public returns (bool) {
        return myTokens[msg.sender].add(value);
    }

    function removeSetUint(uint256 value) public returns (bool) {
        return myTokens[msg.sender].remove(value);
    }

    function containsSetUint(uint256 value) public view returns (bool) {
        return myTokens[msg.sender].contains(value);
    }

    function lengthSetUint() public view returns (uint256) {
        return myTokens[msg.sender].length();
    }

    function atSetUint(uint256 index) public view returns (uint256) {
        return myTokens[msg.sender].at(index);
    }

    mapping(uint256 => EnumerableSet.AddressSet) private tokenBidders;

    function addSetAddr(address value) public returns (bool) {
        return tokenBidders[0].add(value);
    }

    function removeSetAddr(address value) public returns (bool) {
        return tokenBidders[0].remove(value);
    }

    function containsSetAddr(address value) public view returns (bool) {
        return tokenBidders[0].contains(value);
    }

    function lengthSetAddr() public view returns (uint256) {
        return tokenBidders[0].length();
    }

    function atSetAddr(uint256 index) public view returns (address) {
        return tokenBidders[0].at(index);
    }

    // MathUtils
    function within1(uint256 a, uint256 b) public pure returns (bool) {
        return MathUtils.within1(a, b);
    }

    function difference(uint256 a, uint256 b) public pure returns (uint256) {
        return MathUtils.difference(a, b);
    }
}

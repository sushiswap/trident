// SPDX-License-Identifier: MIT

pragma solidity =0.8.2;

import "../libraries/Strings.sol";
import "../libraries/Address.sol";
import "../libraries/UQ112x112.sol";
import "../libraries/FixedPoint.sol";
import "../libraries/SafeERC20.sol";
import "../libraries/EnumerableMap.sol";
import "../libraries/EnumerableSet.sol";
import "../libraries/MirinMath.sol";

import "hardhat/console.sol";

contract LibraryTest {
    using Strings for uint256;
    using Address for address;
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using EnumerableSet for EnumerableSet.UintSet;

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
}

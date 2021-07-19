pragma solidity ^0.8.2;

contract Simplifications {
	// for simplifications
	mapping(uint256 => uint256) public sqrtHarness;

    function sqrt(uint256 x) external view returns (uint256) {
        return sqrtHarness[x];
    }
}
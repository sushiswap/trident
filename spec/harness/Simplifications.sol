pragma solidity ^0.8.2;

contract Simplifications {
	// for simplifications
	mapping(uint256 => uint256) public sqrtHarness;

    function sqrt(uint256 x) external view returns (uint256) {
        // if one of the balances is zero then only the sqrt can be zero
        if (x == 0) {
            return 0;
        }
        
        require(sqrtHarness[x] != 0, "sqrt constraint not met");

        return sqrtHarness[x];
    }
}
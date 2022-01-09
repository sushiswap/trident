pragma solidity ^0.8.2;

contract Simplifications {
	// for simplifications
	mapping(uint256 => uint256) public sqrtHarness;

    function sqrt(uint256 x) public view returns (uint256) {
        // if one of the balances is zero then only the sqrt can be zero
        if (x == 0) {
            return 0;
        }
        
        // TODO: check
        require(sqrtHarness[x] != 0 && sqrtHarness[x] <= x,
                "sqrt constraint not met");

        // require(sqrtHarness[x] * sqrtHarness[x] == x);

        return sqrtHarness[x];
    }
}
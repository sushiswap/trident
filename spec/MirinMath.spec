// spec file
methods {
    sqrt(uint256 a) returns (uint256) envfree
}

rule sqrtSmallerThanUInt128Max(uint256 x) {
    uint256 result = sqrt(x);
    assert(result <= max_uint128);
}

rule sqrtLowerScope(uint256 x) {
    require(x <= max_uint128);
    uint256 result = sqrt(x);
    assert(result <= max_uint64);
}

rule inverseWithinScope(uint256 x) {
    uint256 result = sqrt(x);  // I was hoping this would display the actual value in the Verification Report
    
    assert( result * result  <=  x                       , "Upper Bound violated");
    assert( x                <  (result+1) * (result+1)  , "LowerBound violated");
}

rule inverseWithinLowerScope(uint256 x) {
    require(x >= 1);
    uint256 lowerBound = sqrt(x-1);
    uint256 result = sqrt(x);

    uint256 result_squard = result * result; //inverse

    assert(lowerBound <= result);
}


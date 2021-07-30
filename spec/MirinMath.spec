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

rule multiplication(uint256 x, uint256 y) {
    require(x * y <= max_uint256);
    uint256 result_x = sqrt(x);
    uint256 result_y = sqrt(y);
    uint256 result_xy = sqrt(x * y);
    assert(result_x * result_y == result_xy, "Multiplication rule violated");
}

rule inverseWithinScope(uint256 x) {
    uint256 result = sqrt(x);  // I was hoping this would display the actual value in the Verification Report

    uint256 result_sqrd = result * result;
    mathint result_plus1_sqrd = (result + 1) * (result + 1);

    assert( result_sqrd <=  x               , "Upper Bound violated");
    assert( x           <   result_plus1_sqrd, "LowerBound violated");
}

rule inverseWithinLowerScope(uint256 x) {
    require(x >= 1);
    uint256 lowerBound = sqrt(x-1);
    uint256 result = sqrt(x);

    uint256 result_squard = result * result; //inverse

    assert(lowerBound <= result);
}


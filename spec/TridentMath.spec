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

    mathint result = sqrt(x);

    // not verifiable, but covered testing
    require result < max_uint128;

    mathint result_sqrd = result * result;
    mathint result_plus1_sqrd = (result + 1) * (result + 1);

    assert( result_sqrd <=  x                , "Upper Bound violated");
    assert( x           <   result_plus1_sqrd, "LowerBound violated");
}

// rule inverseWithinScopeSimplified
rule epsilonWithinScope(uint256 x) {

    mathint r = sqrt(x);
    mathint r_sqrd = r*r;
    mathint eps = x - r_sqrd;

    assert(0   <= eps     , "Negative Epsilon");
    assert(eps <  2*r + 1 , "Epsilon to big");
}

rule inverseWithinLowerScope(uint256 x) {
    require(x >= 1);
    uint256 lowerBound = sqrt(x-1);
    uint256 result = sqrt(x);

    uint256 result_squard = result * result; //inverse

    assert(lowerBound <= result);
}


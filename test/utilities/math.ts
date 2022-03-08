import { BigNumber, BigNumberish } from "ethers";
import { ONE, TWO } from "./numbers";

export function sqrt(x: BigNumber) {
  let z = x.add(ONE).div(TWO);
  let y = x;
  while (z.sub(y).isNegative()) {
    y = z;
    z = x.div(z).add(z).div(TWO);
  }
  return y;
}

export function divRoundingUp(numba: BigNumber, denominator: BigNumberish): BigNumber {
  const res = numba.div(denominator);
  const remainder = numba.mod(denominator);
  if (remainder.eq(0)) return res;
  return res.add(1);
}

import { BigNumber } from "ethers";

// used in testing - will have precision errors

export function getNormalPrice(sqrtPrice: BigNumber): number {
  if (sqrtPrice.gt("0x1000000000000000000000000000")) {
    return (
      parseInt(sqrtPrice.div("0x1000000000000000000000000").toString()) ** 2
    );
  } else {
    return (
      (parseInt(sqrtPrice.div("0x1000000000000000000").toString()) /
        16777216) **
      2
    );
  }
}

export function getSqrtX96Price(normalPrice: number): BigNumber {
  return BigNumber.from(Math.floor(normalPrice ** 0.5 * 16777216)).mul(
    "0x1000000000000000000"
  );
}

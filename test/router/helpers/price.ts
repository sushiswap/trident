import { getRandom } from "./random";

const MIN_TOKEN_PRICE = 1e-4
const MAX_TOKEN_PRICE = 1e4
  
export function getTokenPrice(rnd: () => number) {
    const price = getRandom(rnd, MIN_TOKEN_PRICE, MAX_TOKEN_PRICE)
    return price
}
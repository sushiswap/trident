import { Pool } from "@sushiswap/sdk";
import { TokenPrice } from "./helperInterfaces";

/**
 * This function will calculate the prices of tokens in the specified pools
 * @param pool 
 * @returns 
 */
export function getTokenPricesFromPool(pool: Pool) : TokenPrice[] {
    let prices: TokenPrice[] = [];

    const TokenAReserves = pool.reserve0;
    const TokenBReserves = pool.reserve1;

    const TokenAPrice = (Number(TokenAReserves) / Number(TokenBReserves)) * 1e14;
    const TokenBPrice = (Number(TokenBReserves) / Number(TokenAReserves)) * 1e14;

    prices.push({ name: pool.token0.name, address: pool.token0.address, price: TokenAPrice});
    prices.push({ name: pool.token1.name, address: pool.token1.address, price: TokenBPrice});

    return prices;
} 
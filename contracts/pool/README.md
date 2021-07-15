# Trident Pools

The following AMM pool templates can be configured and deployed from their associated `factory` contracts:

## ConstantProductPool

Constant product pools are the the pools that users will be most familar with. Constant product pools are 50/50 pool, meaning you provide 50% of each of Token X and Token Y. In this pool type, swaps occur over an x*y=k constant product formula.

## HybridPool

Hybrid pools allow the user to use a stableswap curve with reduced price impacts. Hybrid pools are best utilized for swapping like-kind assets. Hybrid pools are configurable to allow 2, 3, or any amount of assets.

## ConcentratedLiquidityPool

Concentrated liquidity pools are pools that allow liquidity providers to specify a range in which to provide liquidity in terms of the ratio of Token X to Token Y. The benefit of this design is it will allow liquidity providers to more narrowly scope their liquidity provisioning to maximize swap fees.

## WeightedPool

Weighted pools will be similar to constant product pools with the exception that the pools will allow different weight types. A constant product pool has 50/50 weights of Token X to Token Y. Weighted pools will allow an arbitrary weight of Token X to Token Y. The advantage of this pool type is that it shifts the price impacts by the token weights.

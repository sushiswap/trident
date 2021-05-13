# Mirin: SushiSwap AMMv3
MIRIN, a light alcohol particularly used to create sauces in Japanese cuisine, is the name of our proposed upgraded version of the SushiSwap protocol, or Sushi Protocol v3.

## Overview

### Public/Franchised Pools
In MIRIN, every pair (such as SUSHI-ETH) can have one Public Pool and multiple Franchised Pools.

A public pool is the primary pool and it offers the standard swap fee (0.3% charged and 0.1% goes to xSUSHI holders).

A franchised pool is technically separate, however, and we will give the reigns to the third party exchange to manage its pool in terms of user participation parameters. They can also have the option of offering liquidity providers an additional native governance token, which we will discuss more in further detail in the next heading, and can set transaction fee amounts. The fee structure we would like to bring to your attention is as follows: (0.1% — 10%; 0.05% goes to xSUSHI holders). Although capped at 10%, the exchange are able to hedge their risk by charging participants a fee within the aforementioned range.

### Integrated 1-Click Zap Features

* 1-Click Add liquidity from a single token
* 1-Click Add liquidity from ETH
* 1-Click Remove liquidity to a single token
* 1-Click Remove liquidity to ETH
* 1-Click Migrate from Uniswap
* 1-Click Migrate from Balancer

### New LP Curve Options
For liquidity pool creators, two types of new curves are added so that they can maximize the capital efficiency when providing a new pool to the ecosystem. The constant product curve from SushiSwapV2 will still be available, however, the two new proposed options will be:

#### Constant Product Curve

<img src="https://latex.codecogs.com/gif.latex?k=r_0\cdot%20r_1" />

#### Constant Mean Curve
 
Unlike v2, MIRIN supports each token on a pool can have different weights.
We can define the equation for the invariant like this:

<img src="https://latex.codecogs.com/gif.latex?k=r_0^{w_0}\cdot%20r_1^{w_1}" />

where <img src="https://latex.codecogs.com/gif.latex?r_0" />,
<img src="https://latex.codecogs.com/gif.latex?r_1" />,
<img src="https://latex.codecogs.com/gif.latex?w_0" /> and
<img src="https://latex.codecogs.com/gif.latex?w_1" />, are reserve for first asset, reserve for second asset, weight for first asset and weight for second asset, respectively.

#### Hybrid Curve (Mix of Constant Product + Sum)

Fine-tuned for stable coins. (ex: Curve protocol)

### K3PR-Powered Yield Rebalancing

MIRIN provides you an automatic yield rebalancing tool, powered by K3PR technology. This can benefit you, since you can add a dedicated job to seek out the best LP yields for you. Keepers do the dirty work of all the calculations and comparisons needed to find the highest returns and automatically switches into those optimal pairs.

## RoadMap
- [x] Franchised Pool
- [x] New Curve Options (ETA: late-March)
- [x] K3PR-Powered Yield Rebalancing (ETA: mid-April)
- [ ] Test Coverage (ETA: late-April)
- [ ] Gas Optimization & Internal Audit (ETA: mid-May)
- [ ] Formal Verification (ETA: late-May)

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Contact

* [Andre Cronje](https://twitter.com/AndreCronjeTech/)
* [LevX](https://twitter.com/LevxApp/)
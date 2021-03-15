# Mirin: SushiSwap AMMv3
MIRIN, a light alcohol particularly used to create sauces in Japanese cuisine, is the name of our proposed upgraded version of the SushiSwap protocol, or Sushi Protocol v3.

## Overview

### Capital Efficiency ([Deriswap](https://andrecronje.medium.com/deriswap-capital-efficient-swaps-futures-options-and-loans-ea424b24a41c))
Deriswap combines Swaps, Options, and Loans into a capital efficient single contract, allowing interaction between the two assets that make up the pair.

#### Oracle
The TWAP oracle was expanded to take readings every 30 minutes, this allows us to report realized variance, realized volatility, implied volatility (derived from Realizing Smiles), and price over an arbitrary selected time series.

#### Options
The above derived values allow us to quote Call/Put options using Black Scholes. These are American options, and can be settled at any point in time. Settlement occurs in the pair assets, so a Call needs to buy the full value, and a Put needs to sell the full value.

Combining swaps and Options have an interesting interaction, options are a trade on volatility, trading fees are a hedge against volatility. The pair volatility(+ve trading fees) offsets the losses from settled options (-ve settlement).

Full settlement was also selected since the LPs have a perpetual position on the pair itself, if only profits are settled that is a permanent loss, however if the underlying is settled, that is impermanent loss.
Settlement can occur ITM, or OTM.

Options are tokenized via Non Fungible Tokens (NFT) that allow the trade/creation of secondary markets.

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
* 1-Click Migrate from Balancer `Work in progress`

### K3PR-Powered Yield Rebalancing
> Work in progress.

MIRIN provides you an automatic yield rebalancing tool, powered by K3PR technology. This can benefit you, since you can add a dedicated job to seek out the best LP yields for you. Keepers do the dirty work of all the calculations and comparisons needed to find the highest returns and automatically switches into those optimal pairs.

### New LP Curve Options
For liquidity pool creators, two types of new curves are added so that they can maximize the capital efficiency when providing a new pool to the ecosystem. The constant product curve from SushiSwapV2 will still be available, however, the two new proposed options will be:

#### Arbitrary Weighted Constant Product
> Work in progress
 
Just like Balancer protocol, this curve option can utilize more than just two assets with distinct weights. For instance, for three assets in a pool (Z being the third), the equation would look like this:
```
(X*Y*Z)^(1/3) = K
```
#### Mix of Constant Product + Sum Model
> Work in progress

Fine-tuned for stable coins. (ex: Curve protocol)

## RoadMap
- [x] Franchised Pool
- [x] Capital Efficiency
- [ ] K3PR-Powered Yield Rebalancing (ETA: late-March)
- [ ] New Curve Options (ETA: mid-April)
- [ ] Test Coverage (ETA: late-April)
- [ ] Gas Optimization & Internal Audit (ETA: mid-May)
- [ ] Formal Verification (ETA: late-May)

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Contact

* [Andre Cronje](https://twitter.com/AndreCronjeTech/)
* [LevX](https://twitter.com/LevxApp/)
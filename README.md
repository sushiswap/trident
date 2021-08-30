# Trident: SushiSwap V2

TRIDENT 🔱 is a newly developed AMM from Sushi. Trident is not a fork of any existing AMM -- the SushiSwap core team began development with Andre Cronje as Deriswap. This development continued on as Mirin developed by LevX. On May 12th, 2021 we began building Trident in earnest on the Mirin/Deriswap foundation.

## Deployment

### Kovan

| Contract                   | Address                                    |
| -------------------------- | ------------------------------------------ |
| TridentRouter              | 0x760ef4F484EbF2668001B090291f84A3CDf2f3aa |
| MasterDeployer             | 0x5ad6211CD3fdE39A9cECB5df6f380b8263d1e277 |
| ConstantProductPoolFactory | 0x3c9f107Bf4f79674F6bA8F2bd40E3D2a92424d29 |
| HybridPoolFactory          | 0x042c99C84b00f11A08a07AA9752E083261083A57 |
| IndexPoolFactory           | 0x510039982C76eA66cDca696e995b5308FE932242 |

## Extensibility

Trident is designed as an extensible framework that allows the developers to implement new pool types that conform to the IPool interface. Before launch there will be an EIP submitted for the IPool interface design to standardize pool interfaces across Ethereum. As new pool types are designed or experimented with, they can be added to the AMM so long as they conform to the interface. In this way Trident will at minimum be superset of all AMM pool designs as well as being future proof architecture for Sushi to build on.

## New Pools

Initially Trident has been developed with four pool types.

### ConstantProductPool

Constant product pools are the the pools that users will be most familar with. Constant product pools are 50/50 pool, meaning you provide 50% of each of Token X and Token Y. In this pool type, swaps occur over an x\*y=k constant product formula.

### HybridPool

Hybrid pools allow the user to use a stableswap curve with reduced price impacts. Hybrid pools are best utilized for swapping like-kind assets. Hybrid pools are configurable to allow 2, 3, or any amount of assets.

### ConcentratedLiquidityPool

Concentrated liquidity pools are pools that allow liquidity providers to specify a range in which to provide liquidity in terms of the ratio of Token X to Token Y. The benefit of this design is it will allow liquidity providers to more narrowly scope their liquidity provisioning to maximize swap fees.

### WeightedPool

Weighted pools will be similar to constant product pools with the exception that the pools will allow different weight types. A constant product pool has 50/50 weights of Token X to Token Y. Weighted pools will allow an arbitrary weight of Token X to Token Y. The advantage of this pool type is that it shifts the price impacts by the token weights.

All of these pools will have configurable fees that will allow liquidity providers to choose the pool that best suits their risk profile.

As a gas saving measure we allow the pool deployer to disable TWAP oracles. Architecturally this makes the most sense for commonly used pairs that already have accurate Chainlink price oracles.

## BentoBox Integration

Trident as a native application on our BentoBox platform. BentoBox is our architectural platform that allows us to build complex capital efficient applications on top. BentoBox works by receiving tokens to be utilized in strategies. Meanwhile, a virtual balance on top of BentoBox is used by the application such as Trident. These strategies are returned to the user enabling the most capital efficient experience. Infact, Trident will be the most capital efficient AMM in existence at launch.

So for instance, if a user were to place a limit order or provide liquidity for a pool the underlying tokens would be making additional yield even if no swaps were occurring.

## Architecture

- MasterDeployer is used to add/remove factories for various pool types. Users call MasterDeployer to deploy new pools from the whitelisted factories.
- MasterDeployer also controls the fee percentage that goes to xSUSHI and the fee address.
- MasterDeployer has an owner (ops multisig), that'll control these parameters.
- TridentRouter is the main contract that allows interacting with various pools. It is used to initiate swaps and manage liquidity.
- TridentRouter is the contract that gets whitelisted in BentoBox as the master app.

## Tines: Routing Engine

Tines is our new routing engine designed for our front end. Tines is an efficient multihop multiroute swap router. Tines will query our many pool types and consider factors such as gas costs, price impacts, and graph topology to generate a best price solution.

- Multihop - Tines can swap in between multiple pools to get the best price
- Multiroute - Tines can distribute a trade horizontally to minimize price impacts (slippage)

Different asset types perform better in different pool types. For instance like kind assets such as wBTC and renBTC tend to perform better in hybrid pools. Tines will allow routing more effectively to make multiple pools act as a unified pool resulting in drastically reduced price impacts.

## License (GPL3)

At Sushi we beleive deeply in the open source ecosystem of defi. Our Trident contract set will be GPL3. As a matter of principle Sushi will continue to release all software that we develop or own under GPL3 or other permissive OSS licenses.

## Post Launch Roadmap

- Franchise pools

  - Following the launch of Trident the organization will begin working on franchise pools. Franchise pools are a way to allow institutional to provide liquidity on decentralized exchanges while meeting the needs of their compliance. These pools will be differentiated from the main Trident AMM and will allow institutions to whitelist liquidity providers and swappers.

- Storage Proof TWAP
  - The Trident implementation will allow for the presentation of a storage proof to give two simultaneous snapshots of the cummulative price. To do this, the user using the TWAP price will present a merkle proof where the block root is less than 256 blocks behind the canonical head. On chain the contracts will validate the validity of the storage proof and value to allow an instant TWAP snapshot. We have repurposed another implementation for Kashi and is currently deployed on Polygon. We are worknig on a reduced gas consumption version for a deployment on Ethereum.

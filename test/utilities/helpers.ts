import { Topology } from ".";
import { Contract } from "ethers";
import { getIntegerRandomValue } from ".";
import seedrandom from "seedrandom";
import { createConstantProductPool, createHybridPool } from "./pools";

// getXXTopology (this, that, ...) => topology: list of tokens + prices + pools with reserves
function getTopoplogy(tokens: Contract[], poolCount: number): Topology {
  let topology: Topology = {
    tokens: new Map<string, Contract>(),
    pools: [],
    prices: new Map<string, number>(),
  };

  for (let i = 0; i < tokens.length; i++) {
    const t0 = tokens[i];
    const t1 = tokens[i + 1];

    const randomSeed = Math.floor(Math.random() * 10 + 1);

    //TODO: Generate random price and add to prices map
    topology.tokens.set(t0.address, t0);
    topology.prices.set(t0.address, 4);

    //TODO: Get random pool type and create
    const poolType = Math.floor(Math.random() * 10);
    //let pool = poolType === 0 ? createConstantProductPool() : createHybridPool;

    //topology.pools.push(pool);
  }

  return topology;
}

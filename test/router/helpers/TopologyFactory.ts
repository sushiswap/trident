import { ContractFactory } from "@ethersproject/contracts";
import { BigNumber, Contract } from "ethers";
import { BentoBoxV1, ERC20 } from "../../../types";
import { Topology } from "./interfaces";
import { getRandom } from "../../utilities/random";
import { TridentPoolFactory } from "./TridentPoolFactory";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ConstantProductRPool, getBigNumber, HybridRPool, RPool, RToken, StableSwapRPool } from "@sushiswap/tines";

export const STABLE_TOKEN_PRICE = 1;

export class TopologyFactory {
  private Erc20Factory!: ContractFactory;
  private PoolFactory!: TridentPoolFactory;
  private Bento!: BentoBoxV1;
  private Signer!: SignerWithAddress;

  private MIN_TOKEN_PRICE = 1e-4;
  private MAX_TOKEN_PRICE = 1e4;
  private tokenSupply = getBigNumber(Math.pow(2, 110));

  constructor(
    erc20Factory: ContractFactory,
    poolFactory: TridentPoolFactory,
    bento: BentoBoxV1,
    signer: SignerWithAddress
  ) {
    this.Erc20Factory = erc20Factory;
    this.PoolFactory = poolFactory;
    this.Bento = bento;
    this.Signer = signer;
  }

  public async refreshPools(topology: Topology) {
    const hybridPoolAbi = ["function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1)"];
    const constantPoolAbi = [
      "function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint32 _blockTimestampLast)",
    ];

    for (let index = 0; index < topology.pools.length; index++) {
      const pool = topology.pools[index];

      if (pool instanceof ConstantProductRPool) {
        const poolContract = new Contract(pool.address, constantPoolAbi, this.Signer);
        const [reserve0, reserve1] = await poolContract.getReserves();
        (pool as ConstantProductRPool).updateReserves(reserve0, reserve1);
      } else if (pool instanceof HybridRPool) {
        const poolContract = new Contract(pool.address, hybridPoolAbi, this.Signer);
        const [reserve0, reserve1] = await poolContract.getReserves();
        (pool as HybridRPool).updateReserves(reserve0, reserve1);
      } else if (pool instanceof StableSwapRPool) {
        const reserve0 = await this.Bento.balanceOf(pool.token0.address, pool.address);
        const reserve1 = await this.Bento.balanceOf(pool.token1.address, pool.address);
        (pool as StableSwapRPool).updateReserves(reserve0, reserve1);
      }
    }
  }

  public async getSinglePool(rnd: () => number): Promise<Topology> {
    return await this.getTopoplogy(2, 1, rnd);
  }

  public async getTwoSerialPools(rnd: () => number): Promise<Topology> {
    return await this.getTopoplogy(3, 1, rnd);
  }

  public async getFivePoolBridge(rnd: () => number): Promise<Topology> {
    let topology: Topology = {
      tokens: [],
      prices: [],
      pools: [],
    };

    let prices: number[] = [];
    let tokens: RToken[] = [];
    let tokenContracts: Contract[] = [];

    for (var i = 0; i < 5; ++i) {
      tokens.push({ name: `Token${i}`, address: "" + i });
      prices.push(1);
    }

    for (let i = 0; i < tokens.length; i++) {
      const tokenContract = await this.Erc20Factory.deploy(tokens[0].name, tokens[0].name, this.tokenSupply);
      await tokenContract.deployed();
      tokenContracts.push(tokenContract);
      tokens[i].address = tokenContract.address;
    }

    await this.approveAndFund(tokenContracts);

    const testPool0_1 = await this.PoolFactory.getCPPool(
      tokens[0],
      tokens[1],
      prices[1] / prices[0],
      rnd,
      0.003,
      1_500_0
    );
    const testPool0_2 = await this.PoolFactory.getCPPool(
      tokens[0],
      tokens[2],
      prices[2] / prices[0],
      rnd,
      0.003,
      1_000_0
    );
    const testPool1_2 = await this.PoolFactory.getCPPool(
      tokens[1],
      tokens[2],
      prices[2] / prices[1],
      rnd,
      0.003,
      1_000_000_000
    );
    const testPool1_3 = await this.PoolFactory.getCPPool(
      tokens[1],
      tokens[3],
      prices[3] / prices[1],
      rnd,
      0.003,
      1_000_0
    );
    const testPool2_3 = await this.PoolFactory.getCPPool(
      tokens[2],
      tokens[3],
      prices[3] / prices[2],
      rnd,
      0.003,
      1_500_0
    );

    topology.pools.push(testPool0_1);
    topology.pools.push(testPool0_2);
    topology.pools.push(testPool1_2);
    topology.pools.push(testPool1_3);
    topology.pools.push(testPool2_3);

    return {
      tokens: tokens,
      prices: prices,
      pools: topology.pools,
    };
  }

  public async getRandomTopology(tokenCount: number, density: number, rnd: () => number): Promise<Topology> {
    const tokenContracts: Contract[] = [];

    const tokens: RToken[] = [];
    const prices: number[] = [];
    const pools: RPool[] = [];

    for (var i = 0; i < tokenCount; ++i) {
      tokens.push({ name: `Token${i}`, address: "" + i });
      prices.push(this.getTokenPrice(rnd));
    }

    for (let i = 0; i < tokens.length; i++) {
      const tokenContract = await this.Erc20Factory.deploy(tokens[0].name, tokens[0].name, this.tokenSupply);
      await tokenContract.deployed();
      tokenContracts.push(tokenContract);
      tokens[i].address = tokenContract.address;
    }
    await this.approveAndFund(tokenContracts);

    try {
      for (i = 0; i < tokenCount; ++i) {
        for (var j = i + 1; j < tokenCount; ++j) {
          const r = rnd();
          const token0 = tokens[i];
          const token1 = tokens[j];

          const price0 = prices[i];
          const price1 = prices[j];

          let poolPrice = price0 / price1;

          if (r < density) {
            pools.push(await this.PoolFactory.getRandomPool(token0, token1, poolPrice, rnd, 0.0003));
          }
          if (r < density * density) {
            // second pool
            pools.push(await this.PoolFactory.getRandomPool(token0, token1, poolPrice, rnd, 0.0005));
          }
          if (r < density * density * density) {
            // third pool
            pools.push(await this.PoolFactory.getRandomPool(token0, token1, poolPrice, rnd, 0.00002));
          }
          if (r < Math.pow(density, 4)) {
            // forth pool
            pools.push(await this.PoolFactory.getRandomPool(token0, token1, poolPrice, rnd, 0.0015));
          }
          if (r < Math.pow(density, 5)) {
            // fifth pool
            pools.push(await this.PoolFactory.getRandomPool(token0, token1, poolPrice, rnd, 0.001));
          }
        }
      }
    } catch (error) {
      // console.log('An unknown error occurred generating pools');
      // console.log(pools);
      throw error;
    }

    return {
      tokens,
      prices,
      pools,
    };
  }

  private async getTopoplogy(tokenCount: number, poolVariants: number, rnd: () => number): Promise<Topology> {
    const tokenContracts: Contract[] = [];

    let topology: Topology = {
      tokens: [],
      prices: [],
      pools: [],
    };

    const poolCount = tokenCount - 1;

    for (var i = 0; i < tokenCount; ++i) {
      topology.tokens.push({ name: `Token${i}`, address: "" + i });
      topology.prices.push(this.getTokenPrice(rnd));
    }

    for (let i = 0; i < topology.tokens.length; i++) {
      const tokenContract = await this.Erc20Factory.deploy(
        topology.tokens[0].name,
        topology.tokens[0].name,
        this.tokenSupply
      );
      await tokenContract.deployed();
      tokenContracts.push(tokenContract);
      topology.tokens[i].address = tokenContract.address;
    }

    await this.approveAndFund(tokenContracts);

    let poolType = 0;
    for (i = 0; i < poolCount; i++) {
      for (let index = 0; index < poolVariants; index++) {
        const j = i + 1;

        const token0 = topology.tokens[i];
        const token1 = topology.tokens[j];

        const price0 = topology.prices[i];
        const price1 = topology.prices[j];

        if (poolType % 2 == 0) {
          topology.pools.push(await this.PoolFactory.getHybridPool(token0, token1, price0 / price1, rnd));
        } else {
          topology.pools.push(await this.PoolFactory.getCPPool(token0, token1, price0 / price1, rnd));
        }

        poolType++;
      }
    }

    return topology;
  }

  async getTopologyParallel(rnd: () => number): Promise<Topology> {
    const topology: Topology = {
      tokens: [
        { name: "Token0", address: "0" },
        { name: "Token1", address: "1" },
      ],
      prices: [3, 3.5],
      pools: [],
    };

    const tokenDecimals: number[] = [];
    const tokenContracts: Contract[] = [];
    for (let i = 0; i < topology.tokens.length; i++) {
      const tokenContract = (await this.Erc20Factory.deploy(
        topology.tokens[i].name,
        topology.tokens[i].name,
        this.tokenSupply
      )) as ERC20;
      await tokenContract.deployed();
      tokenContracts.push(tokenContract);
      topology.tokens[i].address = tokenContract.address;
      const decimals = await tokenContract.decimals();
      tokenDecimals.push(decimals);
    }

    await this.approveAndFund(tokenContracts);

    const token0 = topology.tokens[0];
    const token1 = topology.tokens[1];
    const poolPrice = topology.prices[0] / topology.prices[1];

    topology.pools.push(await this.PoolFactory.getCLPool(token0, token1, poolPrice, rnd, 0.003, 60, 1e22));
    topology.pools.push(await this.PoolFactory.getHybridPool(token0, token1, poolPrice, rnd, 1e22));
    topology.pools.push(await this.PoolFactory.getCPPool(token0, token1, poolPrice, rnd, 0.003, 1e22));
    topology.pools.push(
      await this.PoolFactory.getStablePool(
        token0,
        tokenDecimals[0],
        token1,
        tokenDecimals[1],
        poolPrice,
        rnd,
        0.003,
        1e22
      )
    );

    return topology;
  }

  async getTopologySerial(rnd: () => number): Promise<Topology> {
    const topology: Topology = {
      tokens: [
        { name: "Token0", address: "0" },
        { name: "Token1", address: "1" },
        { name: "Token2", address: "2" },
        { name: "Token3", address: "3" },
        { name: "Token4", address: "4" },
      ],
      prices: [
        this.getTokenPrice(rnd),
        this.getTokenPrice(rnd),
        this.getTokenPrice(rnd),
        this.getTokenPrice(rnd),
        this.getTokenPrice(rnd),
      ],
      pools: [],
    };

    const tokenDecimals: number[] = [];
    const tokenContracts: Contract[] = [];
    for (let i = 0; i < topology.tokens.length; i++) {
      const tokenContract = (await this.Erc20Factory.deploy(
        topology.tokens[i].name,
        topology.tokens[i].name,
        this.tokenSupply
      )) as ERC20;
      await tokenContract.deployed();
      tokenContracts.push(tokenContract);
      topology.tokens[i].address = tokenContract.address;
      const decimals = await tokenContract.decimals();
      tokenDecimals.push(decimals);
    }

    await this.approveAndFund(tokenContracts);

    const tok = topology.tokens;
    const prc = topology.prices;

    topology.pools.push(await this.PoolFactory.getCLPool(tok[0], tok[1], prc[0] / prc[1], rnd));
    topology.pools.push(await this.PoolFactory.getHybridPool(tok[1], tok[2], prc[1] / prc[2], rnd));
    topology.pools.push(await this.PoolFactory.getCPPool(tok[2], tok[3], prc[2] / prc[3], rnd));
    topology.pools.push(
      await this.PoolFactory.getStablePool(tok[3], tokenDecimals[3], tok[4], tokenDecimals[4], prc[3] / prc[4], rnd)
    );

    return topology;
  }

  private async approveAndFund(contracts: Contract[]) {
    for (let index = 0; index < contracts.length; index++) {
      const tokenContract = contracts[index];
      await tokenContract.approve(this.Bento.address, this.tokenSupply);
      await this.Bento.deposit(tokenContract.address, this.Signer.address, this.Signer.address, this.tokenSupply, 0);
    }
  }

  private getTokenPrice(rnd: () => number) {
    if (rnd() < 0.7) return STABLE_TOKEN_PRICE;
    return getRandom(rnd, this.MIN_TOKEN_PRICE, this.MAX_TOKEN_PRICE);
  }
}

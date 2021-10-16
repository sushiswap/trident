import { ContractFactory } from "@ethersproject/contracts";
import { Contract } from "ethers";
import { BentoBoxV1 } from "../../../types";
import { Topology } from "./interfaces";
import { getRandom } from "./random";
import { TridentPoolFactory } from "./TridentPoolFactory";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { ConstantProductRPool, getBigNumber, HybridRPool, RPool, RToken } from "@sushiswap/tines";

export class TopologyFactory {
  private Erc20Factory!: ContractFactory;
  private PoolFactory!: TridentPoolFactory;
  private Bento!: BentoBoxV1;
  private Signer!: SignerWithAddress;

  private MIN_TOKEN_PRICE = 1e-4;
  private MAX_TOKEN_PRICE = 1e4;
  private tokenSupply = getBigNumber(Math.pow(2, 110));

  constructor(erc20Factory: ContractFactory, poolFactory: TridentPoolFactory, bento: BentoBoxV1, signer: SignerWithAddress) {
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
      }
    }
  }

  public async getRandomPools(tokenCount: number, variants: number, rnd: () => number): Promise<Topology> {
    return await this.getTopoplogy(tokenCount, variants, rnd);
  }

  public async getSinglePool(rnd: () => number): Promise<Topology> {
    return await this.getTopoplogy(2, 1, rnd);
  }

  public async getTwoSerialPools(rnd: () => number): Promise<Topology> {
    return await this.getTopoplogy(3, 1, rnd);
  }

  public async getThreeSerialPools(rnd: () => number): Promise<Topology> {
    return await this.getTopoplogyWithClPools(4, 1, rnd);
  }

  public async getTwoParallelPools(rnd: () => number): Promise<Topology> {
    return await this.getTopoplogy(2, 2, rnd);
  }

  public async getThreeParallelPools(rnd: () => number): Promise<Topology> {
    return await this.getTopoplogyWithClPools(2, 3, rnd);
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

    const testPool0_1 = await this.PoolFactory.getCPPool(tokens[0], tokens[1], prices[1] / prices[0], rnd, 0.003, 1_500_0);
    const testPool0_2 = await this.PoolFactory.getCPPool(tokens[0], tokens[2], prices[2] / prices[0], rnd, 0.003, 1_000_0);
    const testPool1_2 = await this.PoolFactory.getCPPool(tokens[1], tokens[2], prices[2] / prices[1], rnd, 0.003, 1_000_000_000);
    const testPool1_3 = await this.PoolFactory.getCPPool(tokens[1], tokens[3], prices[3] / prices[1], rnd, 0.003, 1_000_0);
    const testPool2_3 = await this.PoolFactory.getCPPool(tokens[2], tokens[3], prices[3] / prices[2], rnd, 0.003, 1_500_0);

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

  public async getRandomCPTopology(tokenCount: number, density: number, rnd: () => number): Promise<Topology> {
    const tokens: RToken[] = [];
    const prices: number[] = [];
    const pools: RPool[] = [];

    for (var i = 0; i < tokenCount; ++i) {
      tokens.push({ name: `Token${i}`, address: "" + i });
      prices.push(this.getTokenPrice(rnd));
    }

    const tokenContracts: Contract[] = [];
    for (let i = 0; i < tokens.length; i++) {
      const tokenContract = await this.Erc20Factory.deploy(tokens[0].name, tokens[0].name, this.tokenSupply);
      await tokenContract.deployed();
      tokenContracts.push(tokenContract);
      tokens[i].address = tokenContract.address;
    }
    await this.approveAndFund(tokenContracts);

    for (i = 0; i < tokenCount; ++i) {
      for (var j = i + 1; j < tokenCount; ++j) {
        const r = rnd();
        if (r < density) {
          pools.push(await this.PoolFactory.getCPPool(tokens[i], tokens[j], prices[i] / prices[j], rnd, 0.003));
        }
        if (r < density * density) {
          // second pool
          pools.push(await this.PoolFactory.getCPPool(tokens[i], tokens[j], prices[i] / prices[j], rnd, 0.0005));
        }
        if (r < density * density * density) {
          // third pool
          pools.push(await this.PoolFactory.getCPPool(tokens[i], tokens[j], prices[i] / prices[j], rnd, 0.002));
        }
        if (r < Math.pow(density, 4)) {
          // forth pool
          pools.push(await this.PoolFactory.getCPPool(tokens[i], tokens[j], prices[i] / prices[j], rnd, 0.0015));
        }
        if (r < Math.pow(density, 5)) {
          // fifth pool
          pools.push(await this.PoolFactory.getCPPool(tokens[i], tokens[j], prices[i] / prices[j], rnd, 0.001));
        }
      }
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
      const tokenContract = await this.Erc20Factory.deploy(topology.tokens[0].name, topology.tokens[0].name, this.tokenSupply);
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

        // if (poolType % 2 == 0) {
        //   topology.pools.push(await tridentPoolFactory.getCLPool(token0, token1, price0 / price1, rnd));
        // } else
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

  private async getTopoplogyWithClPools(tokenCount: number, poolVariants: number, rnd: () => number): Promise<Topology> {
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
      const tokenContract = await this.Erc20Factory.deploy(topology.tokens[0].name, topology.tokens[0].name, this.tokenSupply);
      await tokenContract.deployed();
      tokenContracts.push(tokenContract);
      topology.tokens[i].address = tokenContract.address;
    }

    await this.approveAndFund(tokenContracts);

    let poolType = 1;
    for (i = 0; i < poolCount; i++) {
      for (let index = 0; index < poolVariants; index++) {
        const j = i + 1;

        const token0 = topology.tokens[i];
        const token1 = topology.tokens[j];

        const price0 = topology.prices[i];
        const price1 = topology.prices[j];

        if (poolType % 2 == 0) {
          topology.pools.push(await this.PoolFactory.getCLPool(token0, token1, price0 / price1, rnd));
        } else if (poolType % 3 == 0) {
          topology.pools.push(await this.PoolFactory.getHybridPool(token0, token1, price0 / price1, rnd));
        } else {
          topology.pools.push(await this.PoolFactory.getCPPool(token0, token1, price0 / price1, rnd));
        }

        poolType++;
      }
    }

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
    const price = getRandom(rnd, this.MIN_TOKEN_PRICE, this.MAX_TOKEN_PRICE);
    return price;
  }
}

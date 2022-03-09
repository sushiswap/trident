import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  BentoBoxV1,
  ConcentratedLiquidityPool,
  ConcentratedLiquidityPoolFactory,
  ConcentratedLiquidityPoolManager,
  ConstantProductPool,
  ConstantProductPoolFactory,
  HybridPool,
  HybridPoolFactory,
  MasterDeployer,
  TickMathMock,
  TridentRouter,
} from "../../../types";

import { choice, getRandom } from "../../utilities/random";
import { ethers } from "hardhat";
import { ContractFactory } from "@ethersproject/contracts";
import { ConstantProductRPool, getBigNumber, HybridRPool, RPool } from "@sushiswap/tines";
import { RToken } from "@sushiswap/sdk";
import { BigNumber } from "ethers";
import { createCLRPool } from "./createCLRPool";
import { getLiquidityForAmount, getMintData, LinkedListHelper } from "../../harness/Concentrated";

export class TridentPoolFactory {
  private ConcentratedLiquidityPool!: ContractFactory;
  private HybridPool!: ContractFactory;
  private ConstantProductPool!: ContractFactory;

  private MasterDeployer!: MasterDeployer;
  private Bento!: BentoBoxV1;
  private Signer!: SignerWithAddress;
  private TridentRouter!: TridentRouter;

  private HybridPoolFactory!: HybridPoolFactory;
  private ConstantPoolFactory!: ConstantProductPoolFactory;

  private ConcentratedPoolFactory!: ConcentratedLiquidityPoolFactory;
  private ConcentratedPoolManager!: ConcentratedLiquidityPoolManager;
  private TickMath!: TickMathMock;

  private MIN_POOL_RESERVE = 1e12;
  private MAX_POOL_RESERVE = 1e23;
  private MIN_POOL_IMBALANCE = 1 / (1 + 1e-3);
  private MAX_POOL_IMBALANCE = 1 + 1e-3;

  constructor(
    signer: SignerWithAddress,
    masterDeployer: MasterDeployer,
    bento: BentoBoxV1,
    tridentRouter: TridentRouter
  ) {
    this.Signer = signer;
    this.MasterDeployer = masterDeployer;
    this.Bento = bento;
    this.TridentRouter = tridentRouter;
  }

  public async init() {
    await this.deployContracts();
  }

  public async getRandomPool(t0: RToken, t1: RToken, price: number, rnd: () => number, fee: number): Promise<RPool> {
    return rnd() > 0.5
      ? await this.getCLPool(t0, t1, price, rnd, fee, 60, 1e20)
      : await this.getCPPool(t0, t1, price, rnd, fee);
  }

  public async getCPPool(
    t0: RToken,
    t1: RToken,
    price: number,
    rnd: () => number,
    fee: number = 0.003,
    reserve: number = 0
  ): Promise<ConstantProductRPool> {
    const feeContract = Math.round(fee * 10_000);
    const imbalance = this.getPoolImbalance(rnd);

    let reserve1;
    let reserve0;

    if (reserve === 0) {
      reserve1 = this.getPoolReserve(rnd);
      reserve0 = reserve1 * price * imbalance;
    } else {
      reserve0 = reserve;
      reserve1 = Math.round(reserve / price);
    }

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256", "bool"],
      [t0.address, t1.address, feeContract, true]
    );

    let deployResult = await (
      await this.MasterDeployer.deployPool(this.ConstantPoolFactory.address, deployData)
    ).wait();

    let poolAddress;

    if (deployResult.events !== undefined) {
      poolAddress = deployResult.events[0].args == undefined ? "" : deployResult.events[0].args[1];
    }

    const constantProductPool = this.ConstantProductPool.attach(poolAddress) as ConstantProductPool;

    await this.Bento.transfer(t0.address, this.Signer.address, constantProductPool.address, getBigNumber(reserve0));
    await this.Bento.transfer(t1.address, this.Signer.address, constantProductPool.address, getBigNumber(reserve1));

    await constantProductPool.mint(ethers.utils.defaultAbiCoder.encode(["address"], [this.Signer.address]));

    return new ConstantProductRPool(
      constantProductPool.address,
      t0,
      t1,
      fee,
      getBigNumber(reserve0),
      getBigNumber(reserve1)
    );
  }

  public async getHybridPool(
    t0: RToken,
    t1: RToken,
    price: number,
    rnd: () => number,
    reserve: number = 0
  ): Promise<HybridRPool> {
    const fee = this.getPoolFee(rnd) * 10_000;
    const A = 7000;
    const imbalance = this.getPoolImbalance(rnd);

    let reserve1;
    let reserve0;

    if (reserve === 0) {
      reserve1 = this.getPoolReserve(rnd);
      reserve0 = reserve1 * price * imbalance;
    } else {
      reserve0 = reserve;
      reserve1 = Math.round(reserve / price);
    }

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint256", "uint256"],
      [t0.address, t1.address, fee, A]
    );

    let deployResult = await (await this.MasterDeployer.deployPool(this.HybridPoolFactory.address, deployData)).wait();

    let poolAddress;

    if (deployResult.events !== undefined) {
      poolAddress = deployResult.events[0].args == undefined ? "" : deployResult.events[0].args[1];
    }

    const hybridPool = this.HybridPool.attach(poolAddress) as HybridPool;

    await this.Bento.transfer(t0.address, this.Signer.address, hybridPool.address, getBigNumber(reserve0));
    await this.Bento.transfer(t1.address, this.Signer.address, hybridPool.address, getBigNumber(reserve1));

    await hybridPool.mint(ethers.utils.defaultAbiCoder.encode(["address"], [this.Signer.address]));

    return new HybridRPool(hybridPool.address, t0, t1, fee / 10_000, A, getBigNumber(reserve0), getBigNumber(reserve1));
  }

  public getCLPoolInstance(address: string): ConcentratedLiquidityPool {
    return this.ConcentratedLiquidityPool.attach(address) as ConcentratedLiquidityPool;
  }

  public async getCLPool(
    t0: RToken,
    t1: RToken,
    price: number,
    rnd: () => number,
    fee = 0.0005,
    tickIncrement = 60,
    reserve: number = 1e25
  ) {
    const flipped = t0.address > t1.address;
    if (flipped) {
      const t = t0;
      t0 = t1;
      t1 = t;
      price = 1 / price;
    }

    const feeContract = Math.round(fee * 10_000);

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint24", "uint160", "uint24"],
      [t0.address, t1.address, feeContract, getBigNumber(Math.sqrt(price) * 2 ** 96), tickIncrement]
    );

    let deployResult = await (
      await this.MasterDeployer.deployPool(this.ConcentratedPoolFactory.address, deployData)
    ).wait();

    let poolAddress;

    if (deployResult.events !== undefined) {
      poolAddress = deployResult.events[0].args == undefined ? "" : deployResult.events[0].args[1];
    }

    const pool = this.ConcentratedLiquidityPool.attach(poolAddress) as ConcentratedLiquidityPool;

    const helper = new LinkedListHelper(-887272);
    const step = 10800;

    const tickSpacing = (await pool.getImmutables())._tickSpacing;
    const poolPrice = (await pool.getPriceAndNearestTicks())._price;
    const tickAtPrice = await this.TickMath.getTickAtSqrtRatio(poolPrice);
    const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
    const nearestEvenValidTick =
      (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

    let lower = nearestEvenValidTick - step;
    let upper = nearestEvenValidTick + step + tickSpacing;

    let addLiquidityParams = {
      lowerOld: helper.insert(lower),
      lower,
      upperOld: helper.insert(upper),
      upper,
      amount0Desired: getBigNumber(reserve / 100),
      amount1Desired: getBigNumber(reserve / 100),
      native0: false,
      native1: false,
      positionOwner: this.ConcentratedPoolManager.address,
      recipient: this.Signer.address,
      positionId: 0,
    };

    const [currentPrice, priceLower, priceUpper] = await this.getPrices(pool, [lower, upper]);

    const liquidity = getLiquidityForAmount(
      priceLower,
      currentPrice,
      priceUpper,
      addLiquidityParams.amount1Desired,
      addLiquidityParams.amount0Desired
    );
    // const mintData = getMintData(addLiquidityParams);
    this.addLiquidityViaManager(pool, addLiquidityParams);

    // await this.TridentRouter.addLiquidityLazy(pool.address, liquidity, mintData);

    addLiquidityParams = helper.setTicks(
      lower - tickIncrement * step,
      upper + tickIncrement * step,
      addLiquidityParams
    );

    await this.addLiquidityViaManager(pool, addLiquidityParams);

    return await createCLRPool(pool);
  }

  private async addLiquidityViaManager(
    pool: ConcentratedLiquidityPool,
    params: {
      lowerOld: number;
      lower: number;
      upperOld: number;
      upper: number;
      amount0Desired: BigNumber;
      amount1Desired: BigNumber;
      native0: boolean;
      native1: boolean;
      positionOwner: string;
      recipient: string;
    }
  ) {
    const {
      amount0Desired,
      amount1Desired,
      native0,
      native1,
      lowerOld,
      lower,
      upperOld,
      upper,
      positionOwner,
      recipient,
    } = params;
    const [currentPrice, priceLower, priceUpper] = await this.getPrices(pool, [lower, upper]);
    const liquidity = getLiquidityForAmount(priceLower, currentPrice, priceUpper, amount1Desired, amount0Desired);
    await this.ConcentratedPoolManager.mint(
      pool.address,
      lowerOld,
      lower,
      upperOld,
      upper,
      amount0Desired,
      amount1Desired,
      native0,
      liquidity,
      0
    );
  }

  private async getPrices(pool: ConcentratedLiquidityPool, ticks: Array<BigNumber | number>) {
    const price = (await pool.getPriceAndNearestTicks())._price;
    const tickPrices = await Promise.all(ticks.map((tick) => this.TickMath.getSqrtRatioAtTick(tick)));
    return [price, ...tickPrices];
  }

  private async deployContracts() {
    //get contract factories for concentrated pool factory, manager
    const ticksContractFactory = await ethers.getContractFactory("Ticks");
    const clPoolManagerFactory = await ethers.getContractFactory("ConcentratedLiquidityPoolManager");
    const tickMath = await ethers.getContractFactory("TickMathMock");
    const dyDxMath = await ethers.getContractFactory("DyDxMath");

    const hybridPoolFactory = await ethers.getContractFactory("HybridPoolFactory");
    this.HybridPool = await ethers.getContractFactory("HybridPool");

    const constantPoolFactory = await ethers.getContractFactory("ConstantProductPoolFactory");
    this.ConstantProductPool = await ethers.getContractFactory("ConstantProductPool");

    const tickLibrary = await ticksContractFactory.deploy();
    const dyDxLibrary = await dyDxMath.deploy();
    const clpLibs = {};
    clpLibs["Ticks"] = tickLibrary.address;
    clpLibs["DyDxMath"] = dyDxLibrary.address;

    const clPoolFactory = await ethers.getContractFactory("ConcentratedLiquidityPoolFactory", { libraries: clpLibs });

    this.ConcentratedLiquidityPool = await ethers.getContractFactory("ConcentratedLiquidityPool", {
      libraries: clpLibs,
    });

    this.ConcentratedPoolManager = (await clPoolManagerFactory.deploy(
      this.MasterDeployer.address,
      this.MasterDeployer.address
    )) as ConcentratedLiquidityPoolManager;
    this.ConcentratedPoolFactory = (await clPoolFactory.deploy(
      this.MasterDeployer.address
    )) as ConcentratedLiquidityPoolFactory;
    this.TickMath = (await tickMath.deploy()) as TickMathMock;

    this.HybridPoolFactory = (await hybridPoolFactory.deploy(this.MasterDeployer.address)) as HybridPoolFactory;
    await this.HybridPoolFactory.deployed();

    this.ConstantPoolFactory = (await constantPoolFactory.deploy(
      this.MasterDeployer.address
    )) as ConstantProductPoolFactory;
    await this.ConstantPoolFactory.deployed();

    await this.whitelistFactories();

    const accounts = await ethers.getSigners();
    await this.Bento.setMasterContractApproval(
      accounts[0].address,
      this.ConcentratedPoolManager.address,
      true,
      "0",
      "0x0000000000000000000000000000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    );
  }

  private async whitelistFactories() {
    await this.Bento.whitelistMasterContract(this.ConcentratedPoolManager.address, true);
    await this.MasterDeployer.addToWhitelist(this.ConcentratedPoolFactory.address);
    await this.MasterDeployer.addToWhitelist(this.HybridPoolFactory.address);
    await this.MasterDeployer.addToWhitelist(this.ConstantPoolFactory.address);
  }

  private getPoolImbalance(rnd: () => number) {
    return getRandom(rnd, this.MIN_POOL_IMBALANCE, this.MAX_POOL_IMBALANCE);
  }

  private getPoolReserve(rnd: () => number) {
    return getRandom(rnd, this.MIN_POOL_RESERVE, this.MAX_POOL_RESERVE);
  }

  private getPoolFee(rnd: () => number) {
    const fees = [0.003, 0.001, 0.0005];
    const cmd = choice(rnd, {
      0: 1,
      1: 1,
      2: 1,
    });
    return fees[parseInt(cmd)];
  }
}

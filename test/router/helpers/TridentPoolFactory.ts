import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import {
  BentoBoxV1,
  ConcentratedLiquidityPool,
  ConcentratedLiquidityPoolFactory,
  ConcentratedLiquidityPoolManager,
  MasterDeployer,
  TickMathTest,
} from "../../../types";
import { MAX_POOL_IMBALANCE, MAX_POOL_RESERVE, MIN_POOL_IMBALANCE, MIN_POOL_RESERVE } from "./constants";
import { getRandom } from "./random";
import { ethers } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { CLRPool, CLTick, getBigNumber } from "@sushiswap/tines";
import { RToken } from "@sushiswap/sdk";
import { getTickAtCurrentPrice, LinkedListHelper, addLiquidityViaRouter } from "../../harness/Concentrated";
import { BigNumber } from "ethers";

export class TridentPoolFactory {
  private ConcentratedLiquidityPool!: ContractFactory;

  private ConcentratedPoolFactory!: ConcentratedLiquidityPoolFactory;
  private ConcentratedPoolManager!: ConcentratedLiquidityPoolManager;
  private MasterDeployer!: MasterDeployer;
  private Bento!: BentoBoxV1;
  private Signer!: SignerWithAddress;
  private TickMath!: TickMathTest;

  constructor(signer: SignerWithAddress, masterDeployer: Contract, bento: Contract) {
    this.Signer = signer;
    this.MasterDeployer = masterDeployer as MasterDeployer;
    this.Bento = bento as BentoBoxV1;
  }

  public async init() {
    await this.deployContracts();
  }

  public async getCLPool(t0: RToken, t1: RToken, price: number, rnd: () => number, fee = 5, tickIncrement = 1) {
    const imbalance = this.getPoolImbalance(rnd);
    const reserve0 = this.getPoolReserve(rnd);
    const reserve1 = reserve0 * price * imbalance;

    const deployData = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint24", "uint160", "uint24"],
      [t0.address, t1.address, fee, BigNumber.from(2).pow(96), tickIncrement]
    );

    let deployResult = await (await this.MasterDeployer.deployPool(this.ConcentratedPoolFactory.address, deployData)).wait();

    let poolAddress;

    if (deployResult.events !== undefined) {
      poolAddress = deployResult.events[0].args == undefined ? "" : deployResult.events[0].args[1];
    }

    const pool = this.ConcentratedLiquidityPool.attach(poolAddress) as ConcentratedLiquidityPool;

    const [sqrtPrice, nearestTickIndex] = await pool.getPriceAndNearestTicks();
    const helper = new LinkedListHelper(-887272);
    const step = 10800;
    const tickSpacing = (await pool.getImmutables())._tickSpacing;
    const tickAtPrice = await this.TickMath.getTickAtSqrtRatio(sqrtPrice);

    const nearestValidTick = tickAtPrice - (tickAtPrice % tickSpacing);
    const nearestEvenValidTick = (nearestValidTick / tickSpacing) % 2 == 0 ? nearestValidTick : nearestValidTick + tickSpacing;

    let lower = nearestEvenValidTick - step;
    let upper = nearestEvenValidTick + step + tickSpacing;

    let addLiquidityParams = {
      pool: pool,
      amount0Desired: getBigNumber(reserve0),
      amount1Desired: getBigNumber(reserve1),
      native: false,
      lowerOld: helper.insert(lower),
      lower,
      upperOld: helper.insert(upper),
      upper,
      positionOwner: this.ConcentratedPoolManager.address,
      recipient: this.Signer.address,
    };

    const ticks: CLTick[] = [];
    let tickIndex = -887272;
    let nearestTick = -2;
    while (1) {
      if (tickIndex === nearestTickIndex) nearestTick = ticks.length;
      const tick = await pool.ticks(tickIndex);
      ticks.push({ index: tickIndex, DLiquidity: parseInt(tick.liquidity.toString()) });
      if (tickIndex === tick.nextTick) break;
      tickIndex = tick.nextTick;
    }

    //await addLiquidityViaRouter(addLiquidityParams);

    const liquidity = parseInt((await pool.liquidity()).toString());

    return new CLRPool(
      pool.address,
      t0,
      t1,
      fee / 1_000_000,
      getBigNumber(reserve0),
      getBigNumber(reserve1),
      89090,
      parseInt(sqrtPrice.toString()) / Math.pow(2, 96),
      nearestTick,
      ticks
    );
  }

  private async deployContracts() {
    //get contract factories for concentrated pool factory, manager
    const ticksContractFactory = await ethers.getContractFactory("Ticks");
    const clPoolManagerFactory = await ethers.getContractFactory("ConcentratedLiquidityPoolManager");
    const tickMath = await ethers.getContractFactory("TickMathTest");

    const tickLibrary = await ticksContractFactory.deploy();
    const clpLibs = {};
    clpLibs["Ticks"] = tickLibrary.address;

    const clPoolFactory = await ethers.getContractFactory("ConcentratedLiquidityPoolFactory", { libraries: clpLibs });

    this.ConcentratedLiquidityPool = await ethers.getContractFactory("ConcentratedLiquidityPool", { libraries: clpLibs });

    this.ConcentratedPoolManager = (await clPoolManagerFactory.deploy(this.MasterDeployer.address)) as ConcentratedLiquidityPoolManager;
    this.ConcentratedPoolFactory = (await clPoolFactory.deploy(this.MasterDeployer.address)) as ConcentratedLiquidityPoolFactory;
    this.TickMath = (await tickMath.deploy()) as TickMathTest;

    //Whitelist factories
    await this.whitelistFactories();
  }

  private async whitelistFactories() {
    await this.Bento.whitelistMasterContract(this.ConcentratedPoolManager.address, true);
    await this.MasterDeployer.addToWhitelist(this.ConcentratedPoolFactory.address);
  }

  private getPoolImbalance(rnd: () => number) {
    return getRandom(rnd, MIN_POOL_IMBALANCE, MAX_POOL_IMBALANCE);
  }

  private getPoolReserve(rnd: () => number) {
    return getRandom(rnd, MIN_POOL_RESERVE, MAX_POOL_RESERVE);
  }
}

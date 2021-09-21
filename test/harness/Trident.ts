import { BigNumber } from "@ethersproject/bignumber";
import { ContractFactory } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { utils } from "ethers";
import { ethers } from "hardhat";
import {
  BentoBoxV1,
  ConcentratedLiquidityPool,
  ConcentratedLiquidityPoolFactory,
  ConcentratedLiquidityPoolManager,
  MasterDeployer,
  TickMathTest,
  TridentRouter,
} from "../../types";
import { ERC20Mock } from "../../types/ERC20Mock";
import { getBigNumber, getFactories, randBetween, sortTokens } from "./helpers";

export class Trident {
  private static _instance: Trident;
  private initialising!: Promise<void>;

  private tokenSupply = getBigNumber(10000000);

  public accounts!: SignerWithAddress[];
  public tokens!: ERC20Mock[];
  public bento!: BentoBoxV1;
  public masterDeployer!: MasterDeployer;
  public router!: TridentRouter;
  public concentratedPoolManager!: ConcentratedLiquidityPoolManager;
  public concentratedPoolFactory!: ConcentratedLiquidityPoolFactory;
  public concentratedPool!: ConcentratedLiquidityPool;
  public tickMath!: TickMathTest;

  public static get Instance() {
    return this._instance || (this._instance = new this());
  }

  public async init() {
    if (this.initialising) return this.initialising;

    this.initialising = new Promise<void>(async (resolve) => {
      this.accounts = await ethers.getSigners();

      const [ERC20, Bento, Deployer, TridentRouter, ConcentratedPoolFactory, ConcentratedPoolManager, TickMath] = await Promise.all(
        getFactories([
          "ERC20Mock",
          "BentoBoxV1",
          "MasterDeployer",
          "TridentRouter",
          "ConcentratedLiquidityPoolFactory",
          "ConcentratedLiquidityPoolManager",
          "TickMathTest",
        ])
      );

      await this.deployTokens(ERC20);
      await this.deployBento(Bento);
      await this.prepareBento();
      await this.deployTridentPeriphery(Deployer, TridentRouter);
      await this.deployConcentratedPeriphery(ConcentratedPoolManager, ConcentratedPoolFactory, TickMath);
      await this.addFactoriesToWhitelist();
      await this.deployConcentratedCore();
      resolve();
    });

    return this.initialising;
  }

  private async deployConcentratedCore() {
    const [token0, token1] = sortTokens(this.tokens);
    const price = BigNumber.from(2).pow(96).mul(randBetween(1, 10000000)).div(randBetween(1, 10000000));
    const deployData = utils.defaultAbiCoder.encode(["address", "address", "uint24", "uint160"], [token0, token1, 30, price]);
    await this.masterDeployer.deployPool(this.concentratedPoolFactory.address, deployData);
  }

  private async deployTokens(ERC20: ContractFactory) {
    this.tokens = await Promise.all([
      ERC20.deploy("TokenA", "TOK", this.tokenSupply),
      ERC20.deploy("TokenB", "TOK", this.tokenSupply),
    ] as Promise<ERC20Mock>[]);
    this.tokens = sortTokens(this.tokens);
  }

  private async deployBento(Bento: ContractFactory) {
    this.bento = (await Bento.deploy(this.tokens[0].address)) as BentoBoxV1;
  }

  private async deployTridentPeriphery(Deployer: ContractFactory, TridentRouter: ContractFactory) {
    this.masterDeployer = (await Deployer.deploy(randBetween(1, 9999), this.accounts[1].address, this.bento.address)) as MasterDeployer;
    this.router = (await TridentRouter.deploy(this.bento.address, this.masterDeployer.address, this.tokens[0].address)) as TridentRouter;
  }

  private async deployConcentratedPeriphery(
    ConcentratedPoolManager: ContractFactory,
    ConcentratedPoolFactory: ContractFactory,
    TickMath: ContractFactory
  ) {
    this.concentratedPoolManager = (await ConcentratedPoolManager.deploy(
      this.bento.address,
      this.tokens[0].address,
      this.masterDeployer.address
    )) as ConcentratedLiquidityPoolManager;
    this.concentratedPoolFactory = (await ConcentratedPoolFactory.deploy(
      this.masterDeployer.address,
      this.concentratedPoolManager.address
    )) as ConcentratedLiquidityPoolFactory;
    // for testing
    this.tickMath = (await TickMath.deploy()) as TickMathTest;
  }

  private async addFactoriesToWhitelist() {
    await this.masterDeployer.addToWhitelist(this.concentratedPoolFactory.address);
    // add others...
  }

  private async prepareBento() {
    await Promise.all([
      this.tokens[0].approve(this.bento.address, this.tokenSupply),
      this.tokens[1].approve(this.bento.address, this.tokenSupply),
    ]);
    await Promise.all([
      this.bento.deposit(this.tokens[0].address, this.accounts[0].address, this.accounts[0].address, this.tokenSupply.div(2), 0),
      this.bento.deposit(this.tokens[1].address, this.accounts[0].address, this.accounts[0].address, this.tokenSupply.div(2), 0),
    ]);
    await this.bento.whitelistMasterContract(this.router.address, true);
    await this.bento.setMasterContractApproval(
      this.accounts[0].address,
      this.router.address,
      true,
      "0",
      "0x0000000000000000000000000000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    );
  }
}

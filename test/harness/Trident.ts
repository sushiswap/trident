import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { ethers } from "hardhat";
import { BentoBoxV1, MasterDeployer, TridentRouter } from "../../types";
import { ERC20Mock } from "../../types/ERC20Mock";
import { getBigNumber, randBetween } from "./helpers";

// const tridnet = Trident.Instance;
export class Trident {
  private static _instance: Trident;
  private initialising!: Promise<void>;

  public accounts!: SignerWithAddress[];
  public tokens!: ERC20Mock[];
  public bento!: BentoBoxV1;
  public masterDeployer!: MasterDeployer;
  public router!: TridentRouter;

  public static get Instance() {
    return this._instance || (this._instance = new this());
  }

  public async init() {
    if (this.initialising) return this.initialising;
    this.initialising = new Promise<void>(async (resolve) => {
      this.accounts = await ethers.getSigners();
      const ERC20 = await ethers.getContractFactory("ERC20Mock");
      const Bento = await ethers.getContractFactory("BentoBoxV1");
      const Deployer = await ethers.getContractFactory("MasterDeployer");
      const TridentRouter = await ethers.getContractFactory("TridentRouter");
      const ConcentratedPoolFactory = await ethers.getContractFactory("ConstantProductPoolFactory");
      const ConcentratedPool = await ethers.getContractFactory("ConstantProductPool");

      this.tokens = await Promise.all(Array(10).fill(ERC20.deploy("Token", "TOK", getBigNumber(10000000))));
      this.bento = (await Bento.deploy(this.tokens[0].address)) as BentoBoxV1;
      this.masterDeployer = (await Deployer.deploy(randBetween(1, 9999), this.accounts[1].address, this.bento.address)) as MasterDeployer;
      this.router = (await TridentRouter.deploy(this.bento.address, this.masterDeployer.address, this.tokens[0].address)) as TridentRouter;

      resolve();
    });
    return this.initialising;
  }
}

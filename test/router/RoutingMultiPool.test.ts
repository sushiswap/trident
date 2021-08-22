import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Contract, ContractFactory } from "ethers";
import seedrandom from "seedrandom";
import {
  getBigNumber,
  getIntegerRandomValue,
  getIntegerRandomValueWithMin,
  areCloseValues,
} from "../utilities";

const MAX_DEPLOYER_FEE = getBigNumber(1, 4);
const rnd: any = seedrandom("8"); // random [0, 1)

describe("MultiPool Router TS == Sol Check", function () {
  let alice: SignerWithAddress,
    feeTo: SignerWithAddress,
    usdt: Contract,
    usdc: Contract,
    weth: Contract,
    bento: Contract,
    masterDeployer: Contract,
    tridentPoolFactory: ContractFactory,
    router: Contract;
});

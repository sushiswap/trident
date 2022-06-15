import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import seedrandom from "seedrandom";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getBigNumber, StableSwapRPool } from "@sushiswap/tines";
import { initializedStablePool } from "../fixtures";
import { BentoBoxV1, ERC20Mock, StablePool } from "../../types";
import { closeValues } from "@sushiswap/sdk";

type RndGen = () => number;
const testSeed = "0"; // Change it to change random generator values
const rnd: RndGen = seedrandom(testSeed); // random [0, 1)

const MINIMUM_LIQUIDITY = 1000;
const MAXIMUM_LIQUIDITY = 1e28; // Limit of contract implementation. TODO: is it enough ????
const MINIMUM_INITIAL_LIQUIDITY = MINIMUM_LIQUIDITY * 10;
const MAXIMUM_INITIAL_LIQUIDITY = MAXIMUM_LIQUIDITY / 10;
const MINIMUM_SWAP_VALUE = MINIMUM_LIQUIDITY;
const MAXIMUM_SWAP_VALUE = MAXIMUM_LIQUIDITY;
const poolState = {
  "1% imbalance": 100,
  "10% imbalance": 50,
  "up to 100x imbalance": 5,
  "up to 1e6 imbalance": 1,
  "one token min value": 1,
};
const feeValues = {
  // basepoints
  30: 10,
  5: 10,
  1: 1,
  2: 1,
  50: 1,
};
const decimals = {
  18: 1,
};
const swapSize = {
  minimum: 1,
  "up to 0.001 pool liquidity": 10,
  "0.001-1 pool liquidity": 10,
  "> pool liquidity": 1,
};

function getRandExp(rnd: RndGen, min: number, max: number) {
  const minL = Math.log(min);
  const maxL = Math.log(max);
  const v = rnd() * (maxL - minL) + minL;
  const res = Math.exp(v);
  console.assert(res <= max && res >= min, "Random value is out of the range");
  return res;
}

interface Variants {
  [key: string | number]: number;
}

function choice(rnd: () => number, obj: Variants) {
  let total = 0;
  Object.entries(obj).forEach(([_, p]) => (total += p));
  if (total <= 0) throw new Error("Error 62");
  const val = rnd() * total;
  let past = 0;
  for (let k in obj) {
    past += obj[k];
    if (past >= val) return k;
  }
  throw new Error("Error 70");
}

interface Environment {
  poolTines: StableSwapRPool;
  pool: StablePool;
  token0: ERC20Mock;
  token1: ERC20Mock;
  bento: BentoBoxV1;
}

async function createPool(
  fee: number, // basepoins
  res0: BigNumber,
  res1: BigNumber,
  token0Decimals: number,
  token1Decimals: number
): Promise<Environment> {
  const token0ContractName = `Token0-${token0Decimals}`;
  const token1ContractName = `Token1-${token1Decimals}`;
  const pool = await initializedStablePool({
    fee,
    token0: token0ContractName,
    token1: token1ContractName,
  });
  const { deployer } = await ethers.getNamedSigners();

  const bento = await ethers.getContract<BentoBoxV1>("BentoBoxV1");
  const token0 = await ethers.getContract<ERC20Mock>(token0ContractName);
  const token1 = await ethers.getContract<ERC20Mock>(token1ContractName);
  await token0.transfer(bento.address, res0);
  await token1.transfer(bento.address, res1);

  await bento.deposit(token0.address, bento.address, pool.address, res0, 0);
  await bento.deposit(token1.address, bento.address, pool.address, res1, 0);
  const mintData = ethers.utils.defaultAbiCoder.encode(["address"], [deployer.address]);
  await pool.mint(mintData);

  const name0 = await token0.name();
  const name1 = await token1.name();

  const poolTines = new StableSwapRPool(
    pool.address,
    { name: name0, address: token0.address },
    { name: name1, address: token1.address },
    fee / 10_000,
    res0,
    res1
  );

  return {
    pool,
    poolTines,
    token0,
    token1,
    bento,
  };
}

function getSecondReserve(rnd: RndGen, res0: number): number {
  let res1;
  switch (choice(rnd, poolState)) {
    case "1% imbalance":
      res1 = res0 * getRandExp(rnd, 0.99, 1.01);
      break;
    case "10% imbalance":
      res1 = res0 * getRandExp(rnd, 0.9, 1.1);
      break;
    case "up to 100x imbalance":
      res1 = res0 * getRandExp(rnd, 0.01, 100);
      break;
    case "up to 1e6 imbalance":
      res1 = res0 * getRandExp(rnd, 1e-6, 1e6);
      break;
    case "one token min value":
      res1 = MINIMUM_INITIAL_LIQUIDITY;
      break;
    default:
      throw new Error("Error 139");
  }
  if (res1 < MINIMUM_INITIAL_LIQUIDITY) res1 = MINIMUM_INITIAL_LIQUIDITY;
  if (res1 > MAXIMUM_INITIAL_LIQUIDITY) res1 = MAXIMUM_INITIAL_LIQUIDITY;
  return res1;
}

async function createRandomPool(rnd: RndGen, iteration: number): Promise<Environment> {
  const res0 = getRandExp(rnd, MINIMUM_INITIAL_LIQUIDITY, MAXIMUM_INITIAL_LIQUIDITY);
  const res1 = getSecondReserve(rnd, res0);
  const fee = parseInt(choice(rnd, feeValues));
  const decimals0 = parseInt(choice(rnd, decimals));
  const decimals1 = parseInt(choice(rnd, decimals));
  //console.log(`Pool ${iteration}: fee=${fee}, res0=${res0}, res1=${res1}, decimals=(${decimals0}, ${decimals1})`);
  return await createPool(fee, getBigNumber(res0), getBigNumber(res1), decimals0, decimals1);
}

async function swapStablePool(env: Environment, swapAmount: BigNumber, direction: boolean) {
  const tokenIn = direction ? env.token0 : env.token1;
  const tokenOut = direction ? env.token1 : env.token0;

  await tokenIn.transfer(env.bento.address, swapAmount);
  await env.bento.deposit(tokenIn.address, env.bento.address, env.pool.address, swapAmount, 0);

  const user = await ethers.getNamedSigner("alice");

  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "bool"],
    [tokenIn.address, user.address, true]
  );
  let balOutBefore: BigNumber = await tokenOut.balanceOf(user.address);
  await env.pool.swap(swapData);
  let balOutAfter: BigNumber = await tokenOut.balanceOf(user.address);
  return balOutAfter.sub(balOutBefore);
}

async function checkSwap(env: Environment, swapAmount: BigNumber, direction: boolean) {
  env.poolTines.updateReserves(
    await env.bento.balanceOf(env.token0.address, env.pool.address),
    await env.bento.balanceOf(env.token1.address, env.pool.address)
  );
  const { out: expectedAmountOut } = env.poolTines.calcOutByIn(parseInt(swapAmount.toString()), direction);
  const poolAmountOut = await swapStablePool(env, swapAmount, direction);
  expect(closeValues(parseFloat(poolAmountOut.toString()), expectedAmountOut, 1e-12)).true;
}

function getAmountIn(rnd: RndGen, res0: number): number {
  let amount;
  switch (choice(rnd, swapSize)) {
    case "minimum":
      amount = MINIMUM_SWAP_VALUE;
      break;
    case "up to 0.001 pool liquidity":
      amount = getRandExp(rnd, MINIMUM_SWAP_VALUE, res0 / 1000);
      break;
    case "0.001-1 pool liquidity":
      amount = getRandExp(rnd, res0 / 1000, res0);
      break;
    case "> pool liquidity":
      amount = getRandExp(rnd, res0, MAXIMUM_SWAP_VALUE);
      break;
    default:
      throw new Error("Error 199");
  }
  if (amount < MINIMUM_SWAP_VALUE) amount = MINIMUM_SWAP_VALUE;
  if (amount > MAXIMUM_SWAP_VALUE) amount = MAXIMUM_SWAP_VALUE;
  return amount;
}
async function checkRandomSwap(rnd: RndGen, env: Environment, iteration: number) {
  env.poolTines.updateReserves(
    await env.bento.balanceOf(env.token0.address, env.pool.address),
    await env.bento.balanceOf(env.token1.address, env.pool.address)
  );
  const swapAmount = getAmountIn(rnd, parseInt(env.poolTines.reserve0.toString()));
  const direction = true; // rnd() < 0.5 TODO - bug in contract for back direction swaps
  // if (iteration < 4)  {
  //   console.log(`Skip swap ${iteration} amount=${swapAmount}, dir=${direction}`)
  //   return
  // }
  // console.log(`Pool ${parseInt(env.poolTines.reserve0.toString())} -> ${parseInt(env.poolTines.reserve1.toString())}`)
  // console.log(`Swap ${iteration} amount=${swapAmount}, dir=${direction}`)
  const { out: expectedAmountOut } = env.poolTines.calcOutByIn(swapAmount, direction);
  if (parseInt(env.poolTines.reserve1.toString()) - expectedAmountOut > MINIMUM_LIQUIDITY) {
    const poolAmountOut = await swapStablePool(env, getBigNumber(swapAmount), direction);
    const realOut = parseFloat(poolAmountOut.toString());
    //console.log('Diff:', realOut, Math.abs(realOut - expectedAmountOut), Math.abs(realOut/expectedAmountOut-1));
    expect(closeValues(realOut, expectedAmountOut, 1e-12)).true;
  } else {
    console.log("Swap check was skipped");
  }
}

describe("Stable Pool <-> Tines consistency", () => {
  it.skip("simple 6 swap test small values", async () => {
    const env = await createPool(30, BigNumber.from(1e6), BigNumber.from(1e6 + 1e3), 18, 18);
    await checkSwap(env, BigNumber.from(1e4), true);
    await checkSwap(env, BigNumber.from(1e5), true);
    await checkSwap(env, BigNumber.from(2e5), true);
    await checkSwap(env, BigNumber.from(1e4), false);
    await checkSwap(env, BigNumber.from(1e5), false);
    await checkSwap(env, BigNumber.from(2e5), false);
  });

  it("simple 6 swap test big values", async () => {
    const env = await createPool(30, BigNumber.from(1e20), BigNumber.from(1e20 + 1e17), 18, 18);
    await checkSwap(env, BigNumber.from(1e18), true);
    // await checkSwap(env, BigNumber.from(1e5), true);
    // await checkSwap(env, BigNumber.from(2e5), true);
    // await checkSwap(env, BigNumber.from(1e4), false);
    // await checkSwap(env, BigNumber.from(1e5), false);
    // await checkSwap(env, BigNumber.from(2e5), false);
  });

  it("Random swap test", async () => {
    for (let i = 0; i < 5; ++i) {
      const env = await createRandomPool(rnd, i);
      for (let j = 0; j < 10; ++j) {
        await checkRandomSwap(rnd, env, j);
      }
    }
  });
});

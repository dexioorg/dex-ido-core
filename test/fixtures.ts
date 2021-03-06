import chai from 'chai'
import { Contract, Wallet } from 'ethers'
import { solidity, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utils'

import TestERC20 from '../build/TestERC20.json'
import DexIDOPool from '../build/DexIDOPool.json'
import DexchangeCore from '../build/DexchangeCore.json'

chai.use(solidity)

interface DexIDOPoolFixture {
  testERC20: Contract
  dexIDOPool: Contract
  dexchangeCore: Contract
}

export async function dexIDOPoolFixture([wallet]: Wallet[]): Promise<DexIDOPoolFixture> {
  const testERC20 = await deployContract(wallet, TestERC20, [expandTo18Decimals(10000000)])
  const dexIDOPool = await deployContract(wallet, DexIDOPool)
  const dexchangeCore = await deployContract(wallet, DexchangeCore)

  return { testERC20, dexIDOPool, dexchangeCore }
}


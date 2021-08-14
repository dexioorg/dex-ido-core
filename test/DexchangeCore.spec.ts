import chai, { expect } from 'chai'
import { Contract, BigNumber } from 'ethers'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'
import { dexIDOPoolFixture } from './fixtures'
import { DAYS, MINUTES, expandTo18Decimals, mineBlock, HOURS } from './utils'

chai.use(solidity)

describe('DexchangeCore Test', () => {
    const provider = new MockProvider({
        ganacheOptions: {
            hardfork: 'istanbul',
            mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
            gasLimit: 9999999,
        },
    })
    const [owner, user, user1, user2] = provider.getWallets()
    const loadFixture = createFixtureLoader([owner], provider)

    let dexchangeCore: Contract
    let dexIDOPool: Contract
    let testERC20: Contract
    beforeEach(async () => {
        const fixture = await loadFixture(dexIDOPoolFixture)
        dexchangeCore = fixture.dexchangeCore
        dexIDOPool = fixture.dexIDOPool
        testERC20 = fixture.testERC20

        const { timestamp: now } = await provider.getBlock('latest')
        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, { value: expandTo18Decimals(100000) })
        await mineBlock(provider, now + 3 * MINUTES)
    })

    it('setRewardRate', async () => {

        await expect(dexchangeCore.setRewardRate(1001))
            .to.be.revertedWith('DexchangeCore::setRewardRate: reward rate use permil')

        await expect(dexchangeCore.setRewardRate(50))
            .to.be.emit(dexchangeCore, "RewardRateChanged");

        expect(await dexchangeCore.rewardRate())
            .to.equal(50);
    })

    it('set pool', async () => {

        await expect(dexchangeCore.setPoolAddress("0x0000000000000000000000000000000000000000"))
            .to.be.revertedWith('DexchangeCore::setPoolAddress: pool address is invalid')

        await expect(dexchangeCore.setPoolAddress(dexIDOPool.address))
            .to.be.emit(dexchangeCore, "PoolChanged");

        expect(await dexchangeCore.poolAddress())
            .to.equal(dexIDOPool.address);

    })

    it('set price', async () => {

        await expect(dexchangeCore.setPrice(user.address, expandTo18Decimals(2)))
            .to.be.revertedWith("DexchangeCore::setPrice: call to non-contract");

        await expect(dexchangeCore.setPrice(testERC20.address, 0))
            .to.be.revertedWith("DexchangeCore::setPrice: price is invalid");

        await expect(dexchangeCore.setPrice(testERC20.address, expandTo18Decimals(2)))
            .to.be.emit(dexchangeCore, "PriceChanged");

        expect(await dexchangeCore.price(testERC20.address)).to.equal(expandTo18Decimals(2))

    })

    it('accept invitation', async () => {
    
        await expect(dexchangeCore.connect(user).acceptInvitation(user1.address))
            .to.be.revertedWith("DexchangeCore::acceptInvitation: pool address did not been set");

        await dexchangeCore.setPoolAddress(dexIDOPool.address)

        await expect(dexchangeCore.connect(user).acceptInvitation(user1.address))
            .to.be.revertedWith("DexchangeCore::acceptInvitation: referrer did not deposit DEX");

        await dexIDOPool.connect(user1).deposit({ value: expandTo18Decimals(2) })
        await dexIDOPool.connect(user2).deposit({ value: expandTo18Decimals(2) })

        await dexchangeCore.connect(user).acceptInvitation(user1.address)

        await expect(dexchangeCore.connect(user).acceptInvitation(user2.address))
            .to.be.revertedWith("DexchangeCore::acceptInvitation: has been accepted invitation");
    })
})

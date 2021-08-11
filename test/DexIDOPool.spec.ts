import chai, { expect } from 'chai'
import { Contract, BigNumber } from 'ethers'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'
import { dexIDOPoolFixture } from './fixtures'
import { DAYS, MINUTES, expandTo18Decimals, mineBlock } from './utils'

chai.use(solidity)

describe('DexIDOPool Test', () => {
    const provider = new MockProvider({
        ganacheOptions: {
            hardfork: 'istanbul',
            mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
            gasLimit: 9999999,
        },
    })
    const [owner, user] = provider.getWallets()
    const loadFixture = createFixtureLoader([owner], provider)

    let testERC20: Contract
    let dexIDOPool: Contract
    beforeEach(async () => {
        const fixture = await loadFixture(dexIDOPoolFixture)
        testERC20 = fixture.testERC20
        dexIDOPool = fixture.dexIDOPool
    })

    it('Deploy pool', async () => {
        const { timestamp: now } = await provider.getBlock('latest')

        await expect(dexIDOPool.deploy(now + 10, 5 * DAYS, 500, { }))
            .to.be.revertedWith('DexIDOPool::deploy: require sending DEX to the pool')

        await expect(dexIDOPool.deploy(now - 10, 5 * DAYS, 500, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::deploy: start time is too soon')

        await expect(dexIDOPool.deploy(now + 10, 0 * DAYS, 500, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::deploy: duration is too short')

        await expect(dexIDOPool.connect(user).deploy(now + 10, 5 * DAYS, 500, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('Ownable: caller is not the owner')

        await expect(dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 500, { value: expandTo18Decimals(105000) }))
            .to.emit(dexIDOPool, 'Deployed')
            .withArgs(1, now + 2 * MINUTES, 5 * DAYS, expandTo18Decimals(100000), expandTo18Decimals(20000), 500, owner.address);
    })

    it('Deposit', async () => {
        const { timestamp: now } = await provider.getBlock('latest')

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 500, { value: expandTo18Decimals(105000) })

        await mineBlock(provider, now + 3 * MINUTES)

        await expect(dexIDOPool.connect(user).deposit(1, { value: 0 }))
            .to.be.revertedWith('DexIDOPool::deposit: require sending DEX to the pool')

        await expect(dexIDOPool.connect(user).deposit(2, { value: expandTo18Decimals(2) }))
            .to.be.revertedWith('DexIDOPool::deposit: the pool is not existed.')

        await dexIDOPool.connect(user).deposit(1, { value: expandTo18Decimals(2) })

        const totalDeposit = await dexIDOPool.totalDeposit(1);
        expect(totalDeposit).to.equal(expandTo18Decimals(2))

        const balance = await dexIDOPool.balance(1, user.address) 
        expect(balance).to.equal(expandTo18Decimals(2))
    })

    it('Withdraw', async () => {
        const { timestamp: now } = await provider.getBlock('latest')

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 500, { value: expandTo18Decimals(105000) })

        await mineBlock(provider, now + 3 * MINUTES)

        await dexIDOPool.connect(user).deposit(1, { value: expandTo18Decimals(2) })

        await mineBlock(provider, now + 3 * DAYS)

        await expect(dexIDOPool.connect(user).withdraw(1))
            .to.be.revertedWith('DexIDOPool::withdraw: the pool is not over yet.')

        await mineBlock(provider, now + 6 * DAYS)

        await dexIDOPool.connect(user).withdraw(1)

        const totalDeposit = await dexIDOPool.totalDeposit(1);
        expect(totalDeposit).to.equal(expandTo18Decimals(0))

        const balance = await dexIDOPool.balance(1, user.address) 
        expect(balance).to.equal(expandTo18Decimals(0))
    })
    
    it('Contract stoppable', async () => {

        await dexIDOPool.stop()
        expect(await dexIDOPool.stopped()).to.equal(true);

        var { timestamp: now } = await provider.getBlock('latest')

        await expect(dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 50000, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::stoppable: contract has been stopped.')

        now = now + 3 * MINUTES
        await mineBlock(provider, now)

        await expect(dexIDOPool.connect(user).withdraw(0))
            .to.be.revertedWith('DexIDOPool::stoppable: contract has been stopped.');

        await dexIDOPool.start()
        expect(await dexIDOPool.stopped()).to.equal(false);

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 500, { value: expandTo18Decimals(100000) })
    })
})

import chai, { expect } from 'chai'
import { Contract, BigNumber } from 'ethers'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'
import { dexIDOPoolFixture } from './fixtures'
import { DAYS, MINUTES, expandTo18Decimals, mineBlock, HOURS } from './utils'

chai.use(solidity)

describe('DexIDOPool Test', () => {
    const provider = new MockProvider({
        ganacheOptions: {
            hardfork: 'istanbul',
            mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
            gasLimit: 9999999,
        },
    })
    const [owner, user, user1, user2, user3] = provider.getWallets()
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

        await expect(dexIDOPool.deploy(now + 10, 5 * DAYS, { }))
            .to.be.revertedWith('DexIDOPool::deploy: require sending DEX to the pool')

        await expect(dexIDOPool.deploy(now - 10, 5 * DAYS, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::deploy: start time is too soon')

        await expect(dexIDOPool.deploy(now + 10, 0 * DAYS, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::deploy: duration is too short')

        await expect(dexIDOPool.connect(user).deploy(now + 10, 5 * DAYS, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('Ownable: caller is not the owner')

        await expect(dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, { value: expandTo18Decimals(100000) }))
            .to.emit(dexIDOPool, 'Deployed')
            .withArgs(1, now + 2 * MINUTES, 5 * DAYS, expandTo18Decimals(100000), expandTo18Decimals(20000), owner.address);
    })

    it('Deposit', async () => {
        const { timestamp: now } = await provider.getBlock('latest')

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, { value: expandTo18Decimals(100000) })

        const poolNum = await dexIDOPool.poolCount()

        await mineBlock(provider, now + 3 * MINUTES)

        await expect(dexIDOPool.connect(user).deposit(poolNum, { value: 0 }))
            .to.be.revertedWith('DexIDOPool::deposit: require sending DEX to the pool')

        await expect(dexIDOPool.connect(user).deposit(poolNum + 1, { value: expandTo18Decimals(2) }))
            .to.be.revertedWith('DexIDOPool::deposit: the pool is not existed.')

        await dexIDOPool.connect(user).deposit(poolNum, { value: expandTo18Decimals(2) })

        const totalDeposit = await dexIDOPool.totalDeposit(poolNum);
        expect(totalDeposit).to.equal(expandTo18Decimals(2))

        const balance = await dexIDOPool.balanceOf(poolNum, user.address) 
        expect(balance).to.equal(expandTo18Decimals(2))
    })

    it('Withdraw', async () => {
        const { timestamp: now } = await provider.getBlock('latest')

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, { value: expandTo18Decimals(100000) })

        const poolNum = await dexIDOPool.poolCount()

        await mineBlock(provider, now + 3 * MINUTES)

        await expect(dexIDOPool.connect(user).withdraw(poolNum, 0))
            .to.be.revertedWith('DexIDOPool::withdraw: the pool is not over, amount is invalid.')
            
        await dexIDOPool.connect(user).deposit(poolNum, { value: expandTo18Decimals(2) })
            
        await expect(dexIDOPool.connect(user).withdraw(poolNum, expandTo18Decimals(3)))
            .to.be.revertedWith('DexIDOPool::withdraw: the amount deposited today is not enough.')
        
        await dexIDOPool.connect(user).withdraw(poolNum, expandTo18Decimals(1))

        await mineBlock(provider, now + 3 * DAYS)

        await expect(dexIDOPool.connect(user).withdraw(poolNum, 0))
            .to.be.revertedWith('DexIDOPool::withdraw: the pool is not over, amount is invalid.')

        await mineBlock(provider, now + 6 * DAYS)

        await dexIDOPool.connect(user).withdraw(poolNum, 1)

        const totalDeposit = await dexIDOPool.totalDeposit(poolNum);
        expect(totalDeposit).to.equal(expandTo18Decimals(0))

        const balance = await dexIDOPool.balanceOf(poolNum, user.address) 
        expect(balance).to.equal(expandTo18Decimals(0))
    })
    
    it('Contract stoppable', async () => {

        await dexIDOPool.stop()
        expect(await dexIDOPool.stopped()).to.equal(true);

        var { timestamp: now } = await provider.getBlock('latest')

        await expect(dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::stoppable: contract has been stopped.')

        const poolNum = await dexIDOPool.poolCount()

        now = now + 3 * MINUTES
        await mineBlock(provider, now)

        await expect(dexIDOPool.connect(user).withdraw(poolNum, 0))
            .to.be.revertedWith('DexIDOPool::stoppable: contract has been stopped.');

        await dexIDOPool.start()
        expect(await dexIDOPool.stopped()).to.equal(false);

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, { value: expandTo18Decimals(100000) })
    })

    it('Account available exchange DEX amount', async () => {
        var { timestamp: now } = await provider.getBlock('latest')
        await dexIDOPool.deploy(now + 2 * MINUTES, 180 * DAYS, { value: expandTo18Decimals(1800000) })
        const poolNum = await dexIDOPool.poolCount()
        await mineBlock(provider, now + 2 * MINUTES)
        
        // DAY 1
        await dexIDOPool.connect(user).deposit(poolNum, { value: expandTo18Decimals(40000) })
        await dexIDOPool.connect(user1).deposit(poolNum, { value: expandTo18Decimals(30000) })
        await dexIDOPool.connect(user2).deposit(poolNum, { value: expandTo18Decimals(20000) })
        await dexIDOPool.connect(user3).deposit(poolNum, { value: expandTo18Decimals(10000) })

        expect(await dexIDOPool.totalDeposit(poolNum)).to.equal(expandTo18Decimals(100000))

        expect(await dexIDOPool.availableToExchange(poolNum, user.address))
            .to.equal(expandTo18Decimals(0))
        expect(await dexIDOPool.availableToExchange(poolNum, user1.address))
            .to.equal(expandTo18Decimals(0))
        expect(await dexIDOPool.availableToExchange(poolNum, user2.address))
            .to.equal(expandTo18Decimals(0))
        expect(await dexIDOPool.availableToExchange(poolNum, user3.address))
            .to.equal(expandTo18Decimals(0))

        // DAY 2
        await mineBlock(provider, now + 1 * DAYS + 1 * HOURS)

        // await dexIDOPool.connect(user).deposit(poolNum, { value: expandTo18Decimals(0) })
        await dexIDOPool.connect(user1).deposit(poolNum, { value: expandTo18Decimals(5000) })
        // await dexIDOPool.connect(user2).deposit(poolNum, { value: expandTo18Decimals(0) })
        await dexIDOPool.connect(user3).deposit(poolNum, { value: expandTo18Decimals(5000) })

        expect(await dexIDOPool.totalDeposit(poolNum)).to.equal(expandTo18Decimals(110000))

        expect(await dexIDOPool.availableToExchange(poolNum, user.address))
            .to.equal(expandTo18Decimals(4000))
        expect(await dexIDOPool.availableToExchange(poolNum, user1.address))
            .to.equal(expandTo18Decimals(3000))
        expect(await dexIDOPool.availableToExchange(poolNum, user2.address))
            .to.equal(expandTo18Decimals(2000))
        expect(await dexIDOPool.availableToExchange(poolNum, user3.address))
            .to.equal(expandTo18Decimals(1000))

        // DAY 3
        await mineBlock(provider, now + 2 * DAYS + 1 * HOURS)

        // await dexIDOPool.connect(user).deposit(poolNum, { value: expandTo18Decimals(0) })
        // await dexIDOPool.connect(user1).deposit(poolNum, { value: expandTo18Decimals(5000) })
        // await dexIDOPool.connect(user2).deposit(poolNum, { value: expandTo18Decimals(0) })
        // await dexIDOPool.connect(user3).deposit(poolNum, { value: expandTo18Decimals(5000) })

        expect(await dexIDOPool.totalDeposit(poolNum)).to.equal(expandTo18Decimals(110000))

        // expect(await dexIDOPool.availableToExchange(poolNum, user.address))
        //     .to.equal(3636363636363636363636)
        // expect(await dexIDOPool.availableToExchange(poolNum, user1.address))
        //     .to.equal(expandTo18Decimals(2273))
        // expect(await dexIDOPool.availableToExchange(poolNum, user2.address))
        //     .to.equal(expandTo18Decimals(2727))
        // expect(await dexIDOPool.availableToExchange(poolNum, user3.address))
        //     .to.equal(expandTo18Decimals(1364))
    })
})

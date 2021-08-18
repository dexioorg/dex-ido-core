import chai, { expect } from 'chai'
import { Contract } from 'ethers'
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
    let dexchangeCore: Contract
    let dexIDOPool: Contract
    beforeEach(async () => {
        const fixture = await loadFixture(dexIDOPoolFixture)
        dexchangeCore = fixture.dexchangeCore
        testERC20 = fixture.testERC20
        dexIDOPool = fixture.dexIDOPool
    })

    it('Deploy pool', async () => {
        const { timestamp: now } = await provider.getBlock('latest')

        await expect(dexIDOPool.deploy(now + 10, 5 * DAYS, 50, dexchangeCore.address, {}))
            .to.be.revertedWith('DexIDOPool::deploy: require sending DEX to the pool')

        await expect(dexIDOPool.deploy(now - 10, 5 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::deploy: start time is too soon')

        await expect(dexIDOPool.deploy(now + 10, 0 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::deploy: duration is too short')

        await expect(dexIDOPool.deploy(now + 10, 5 * DAYS, 1001, dexchangeCore.address, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::deploy: reward rate use permil')

        await expect(dexIDOPool.connect(user).deploy(now + 10, 5 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('Ownable: caller is not the owner')

        await expect(dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(100000) }))
            .to.emit(dexIDOPool, 'Deployed')
            .withArgs(now + 2 * MINUTES, 5 * DAYS, expandTo18Decimals(100000), expandTo18Decimals(20000), 50, owner.address, dexchangeCore.address);
    })

    it('Deposit', async () => {
        const { timestamp: now } = await provider.getBlock('latest')

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(100000) })

        await mineBlock(provider, now + 3 * MINUTES)

        await expect(dexIDOPool.connect(user).deposit({ value: 0 }))
            .to.be.revertedWith('DexIDOPool::deposit: require sending DEX to the pool')

        await dexIDOPool.connect(user).deposit({ value: expandTo18Decimals(2) })

        const totalDeposit = await dexIDOPool.totalDeposit();
        expect(totalDeposit).to.equal(expandTo18Decimals(2))

        const balance = await dexIDOPool.balanceOf(user.address)
        expect(balance).to.equal(expandTo18Decimals(2))
    })

    it('Withdraw', async () => {
        const { timestamp: now } = await provider.getBlock('latest')

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(100000) })

        await mineBlock(provider, now + 3 * MINUTES)

        await expect(dexIDOPool.connect(user).withdraw(0))
            .to.be.revertedWith('DexIDOPool::withdraw: the pool is not over, amount is invalid.')

        await dexIDOPool.connect(user).deposit({ value: expandTo18Decimals(2) })

        await expect(dexIDOPool.connect(user).withdraw(expandTo18Decimals(3)))
            .to.be.revertedWith('DexIDOPool::withdraw: the amount deposited today is not enough.')

        await dexIDOPool.connect(user).withdraw(expandTo18Decimals(1))

        await mineBlock(provider, now + 3 * DAYS)

        await expect(dexIDOPool.connect(user).withdraw(0))
            .to.be.revertedWith('DexIDOPool::withdraw: the pool is not over, amount is invalid.')

        await mineBlock(provider, now + 6 * DAYS)

        const balanceBefore = await provider.getBalance(user.address)
        await dexIDOPool.connect(user).withdraw(1)
        const balanceAfter = await provider.getBalance(user.address)

        expect(balanceAfter.div(balanceBefore)).equal(1)

        const totalDeposit = await dexIDOPool.totalDeposit();
        expect(totalDeposit).to.equal(expandTo18Decimals(0))

        const balance = await dexIDOPool.balanceOf(user.address)
        expect(balance).to.equal(expandTo18Decimals(0))
    })

    it('Contract stoppable', async () => {

        await dexIDOPool.stop()
        expect(await dexIDOPool.stopped()).to.equal(true);

        var { timestamp: now } = await provider.getBlock('latest')

        await expect(dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(100000) }))
            .to.be.revertedWith('DexIDOPool::stoppable: contract has been stopped.')

        now = now + 3 * MINUTES
        await mineBlock(provider, now)

        await expect(dexIDOPool.connect(user).withdraw(0))
            .to.be.revertedWith('DexIDOPool::stoppable: contract has been stopped.');

        await expect(dexIDOPool.connect(user).start())
            .to.be.revertedWith("Ownable: caller is not the owner")

        await dexIDOPool.start()
        expect(await dexIDOPool.stopped()).to.equal(false);

        await dexIDOPool.deploy(now + 2 * MINUTES, 5 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(100000) })
    })

    it('Account available exchange DEX amount', async () => {
        var { timestamp: now } = await provider.getBlock('latest')
        await dexIDOPool.deploy(now + 2 * MINUTES, 180 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(1800000) })
        await mineBlock(provider, now + 2 * MINUTES)

        // DAY 1
        await dexIDOPool.connect(user).deposit({ value: expandTo18Decimals(40000) })
        await dexIDOPool.connect(user1).deposit({ value: expandTo18Decimals(30000) })
        await dexIDOPool.connect(user2).deposit({ value: expandTo18Decimals(20000) })
        await dexIDOPool.connect(user3).deposit({ value: expandTo18Decimals(10000) })

        expect(await dexIDOPool.totalDeposit()).to.equal(expandTo18Decimals(100000))

        expect(await dexIDOPool.availableToExchange(user.address))
            .to.equal(expandTo18Decimals(0))
        expect(await dexIDOPool.availableToExchange(user1.address))
            .to.equal(expandTo18Decimals(0))
        expect(await dexIDOPool.availableToExchange(user2.address))
            .to.equal(expandTo18Decimals(0))
        expect(await dexIDOPool.availableToExchange(user3.address))
            .to.equal(expandTo18Decimals(0))

        // DAY 2
        await mineBlock(provider, now + 1 * DAYS + 1 * HOURS)

        // await dexIDOPool.connect(user).deposit({ value: expandTo18Decimals(0) })
        await dexIDOPool.connect(user1).deposit({ value: expandTo18Decimals(5000) })
        // await dexIDOPool.connect(user2).deposit({ value: expandTo18Decimals(0) })
        await dexIDOPool.connect(user3).deposit({ value: expandTo18Decimals(5000) })

        expect(await dexIDOPool.totalDeposit()).to.equal(expandTo18Decimals(110000))

        expect(await dexIDOPool.availableToExchange(user.address))
            .to.equal(expandTo18Decimals(4000))
        expect(await dexIDOPool.availableToExchange(user1.address))
            .to.equal(expandTo18Decimals(3000))
        expect(await dexIDOPool.availableToExchange(user2.address))
            .to.equal(expandTo18Decimals(2000))
        expect(await dexIDOPool.availableToExchange(user3.address))
            .to.equal(expandTo18Decimals(1000))

        // DAY 3
        await mineBlock(provider, now + 2 * DAYS + 1 * HOURS)

        // await dexIDOPool.connect(user).deposit({ value: expandTo18Decimals(0) })
        // await dexIDOPool.connect(user1).deposit({ value: expandTo18Decimals(5000) })
        // await dexIDOPool.connect(user2).deposit({ value: expandTo18Decimals(0) })
        // await dexIDOPool.connect(user3).deposit({ value: expandTo18Decimals(5000) })

        expect(await dexIDOPool.totalDeposit()).to.equal(expandTo18Decimals(110000))

        // expect(await dexIDOPool.availableToExchange(user.address))
        //     .to.equal(3636363636363636363636)
        // expect(await dexIDOPool.availableToExchange(user1.address))
        //     .to.equal(expandTo18Decimals(2273))
        // expect(await dexIDOPool.availableToExchange(user2.address))
        //     .to.equal(expandTo18Decimals(2727))
        // expect(await dexIDOPool.availableToExchange(user3.address))
        //     .to.equal(expandTo18Decimals(1364))
    })

    it('Accept invitation', async () => {

        var { timestamp: now } = await provider.getBlock('latest')
        await dexIDOPool.deploy(now + 2 * MINUTES, 180 * DAYS, 50, dexchangeCore.address, { value: expandTo18Decimals(1800000) })
        await mineBlock(provider, now + 2 * MINUTES)
        
        await expect(dexIDOPool.connect(user).accept(user1.address))
            .to.be.revertedWith("DexIDOPool::accept: referrer did not deposit DEX");

        await dexIDOPool.connect(user1).deposit({ value: expandTo18Decimals(2) })
        await dexIDOPool.connect(user2).deposit({ value: expandTo18Decimals(2) })

        await dexIDOPool.connect(user).accept(user1.address)

        await expect(dexIDOPool.connect(user).accept(user2.address))
            .to.be.revertedWith("DexIDOPool::accept: has been accepted invitation");
    })

    it('Transfer', async () => {

        await expect(dexIDOPool.connect(user).transfer(testERC20.address, user1.address, 1000))
            .to.be.revertedWith("Ownable: caller is not the owner")

        await expect(dexIDOPool.connect(owner).transfer(user1.address, user2.address, 1000))
            .to.be.revertedWith("DexIDOPool::transfer: call to non-contract.")

        await expect(dexIDOPool.connect(owner).transfer(testERC20.address, user1.address, 0))
            .to.be.revertedWith("DexIDOPool::transfer: input amount is invalid.")

        await expect(dexIDOPool.connect(owner).transfer(testERC20.address, user1.address, 1000))
            .to.be.revertedWith("DexIDOPool::transfer: token balance is insufficient")

        expect(await testERC20.balanceOf(dexIDOPool.address)).to.equal(0)
        await testERC20.transfer(dexIDOPool.address, expandTo18Decimals(2000))
        expect(await testERC20.balanceOf(dexIDOPool.address)).to.equal(expandTo18Decimals(2000))
        
        expect(await testERC20.balanceOf(user.address)).to.equal(0)
        await dexIDOPool.connect(owner).transfer(testERC20.address, user.address, expandTo18Decimals(1000))
        expect(await testERC20.balanceOf(user.address)).to.equal(expandTo18Decimals(1000))
    })

    it('Refund', async () => {

        await expect(dexIDOPool.connect(user).refund(user1.address, 1000))
            .to.be.revertedWith("Ownable: caller is not the owner")

        await expect(dexIDOPool.connect(owner).refund(user1.address, 0))
            .to.be.revertedWith("DexIDOPool::refund: input amount is invalid.")

        await expect(dexIDOPool.connect(owner).refund(user1.address, 1000))
            .to.be.revertedWith("DexIDOPool::refund: balance is insufficient")

        expect(await provider.getBalance(dexIDOPool.address)).to.equal(0)
        // console.log('balance' , await (await provider.getBalance(owner.address)).toString())
        await owner.sendTransaction({ to: dexIDOPool.address, value: expandTo18Decimals(2000) })
        expect(await provider.getBalance(dexIDOPool.address)).to.equal(expandTo18Decimals(2000))
        
        expect(await provider.getBalance(user.address)).to.equal(0)
        await dexIDOPool.connect(owner).refund(user.address, expandTo18Decimals(1000))
        expect(await provider.getBalance(user.address)).to.equal(expandTo18Decimals(1000))

    })
})

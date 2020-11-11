/* global it, contract, artifacts, assert, web3 */
const { deployProxy} = require('@openzeppelin/truffle-upgrades')

const WithdrawalPool = artifacts.require('./WithdrawalPool.sol')
const MasterTransferRegistry = artifacts.require('./MasterTransferRegistry.sol')
const MintableERC20 = artifacts.require('./MintableERC20.sol')

const factoryJson = require('@uniswap/v2-core/build/UniswapV2Factory.json')
const pairJson = require('@uniswap/v2-core/build/UniswapV2Pair.json')
const contractInit = require('@truffle/contract')
const UniswapV2Factory = contractInit(factoryJson)
const UniswapV2Pair = contractInit(pairJson)
UniswapV2Factory.setProvider(web3.currentProvider)
UniswapV2Pair.setProvider(web3.currentProvider)

const { blockTime, moveForwardTime, getRandomSalt, assertEventOfType } = require('./helpers/utils')
const BN = web3.utils.BN
const _1e18 = new BN('1000000000000000000')

contract('WithdrawalPool', (accounts) => {

  let uni, pool, weth, nectar, registry, factory

  beforeEach('redeploy contract', async function () {
    weth = await MintableERC20.new('Wrapped_ETH', 'WETH')
    nectar = await MintableERC20.new('Nectar', 'NEC')

    factory = await UniswapV2Factory.new(accounts[0], { from: accounts[0] })

    const tx = await factory.createPair(weth.address, nectar.address, { from: accounts[0] })
    assertEventOfType(tx, 'PairCreated', 0)
    uni = await UniswapV2Pair.at(tx.logs[0].args.pair)

    await weth.mint(accounts[0], _1e18.mul(new BN(100)))
    await nectar.mint(accounts[0], _1e18.mul(new BN(100000)))
    await weth.transfer(uni.address, _1e18.mul(new BN(40)))
    await nectar.transfer(uni.address, _1e18.mul(new BN(50000)))
    await uni.mint(accounts[0], { from: accounts[0] })

    registry = await deployProxy(MasterTransferRegistry, [factory.address, weth.address, nectar.address])
    await registry.createNewPool(weth.address)
    await weth.mint(accounts[1], _1e18.mul(new BN(5000)))
    const poolAddress = await registry.tokenPools(weth.address)
    pool = await WithdrawalPool.at(poolAddress)

    await moveForwardTime(86400)
    await weth.transfer(uni.address, _1e18.mul(new BN(4)))
    await nectar.transfer(uni.address, _1e18.mul(new BN(5000)))
    await uni.mint(accounts[0], { from: accounts[0] })

    await registry.updateExchangeRate(nectar.address)
    const price = await registry.necExchangeRate(weth.address, _1e18)
    const expectedRatio = new BN(1250)
    assert.equal(price.toString(), _1e18.mul(expectedRatio).toString(), 'Price was not updated')
  })

  it('deploy: pool gets deployed and has correct pool token address', async () => {
    const address = await pool.poolToken()
    const masterRegistry = await pool.transferRegistry()
    const totalPoolSize = await pool.totalPoolSize()
    assert.equal(address, weth.address, 'Pool token not set')
    assert.equal(masterRegistry, registry.address, 'Master not correctly set in pool contract')
    assert.equal(totalPoolSize, 0, 'There are already deposits?')
  })

  it('joinPool: when depositing tokens to the pool, the tokens are transfered into the contract, and correct number of LP tokens are minted for depositor', async () => {
    const depositAmount = _1e18.mul(new BN(1000))
    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[1] })
    const newBalance = await weth.balanceOf(accounts[1])
    assert.equal(newBalance.toString(), _1e18.mul(new BN(5000)).sub(depositAmount).toString(), 'Token not transfered')

    const lpwethBalance = await pool.balanceOf(accounts[1])
    assert.equal(lpwethBalance.toString(), _1e18.mul(new BN(100)).toString(), 'Initial mint for first depositor was not 100')
  })

  it('joinPool: multiple depositors get credited correct ratio of LP tokens', async () => {
    const depositAmount = _1e18.mul(new BN(1000))
    await weth.transfer(accounts[2], depositAmount, { from: accounts[1] })
    await weth.transfer(accounts[3], _1e18.mul(new BN(400)), { from: accounts[1] })
    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    await weth.approve(pool.address, depositAmount, { from: accounts[2] })
    await weth.approve(pool.address, depositAmount, { from: accounts[3] })

    await pool.joinPool(depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[2] })
    await pool.joinPool(_1e18.mul(new BN(400)), { from: accounts[3] })

    const lpTokenBalance1 = await pool.balanceOf(accounts[1])
    const lpTokenBalance2 = await pool.balanceOf(accounts[2])
    const lpTokenBalance3 = await pool.balanceOf(accounts[3])
    assert.equal(lpTokenBalance1.toString(), _1e18.mul(new BN(100)).toString(), 'Initial mint for first depositor was not 100')
    assert.equal(lpTokenBalance2.toString(), _1e18.mul(new BN(100)).toString(), 'Second depositor not give LP tokens at correct ratio')
    assert.equal(lpTokenBalance3.toString(), _1e18.mul(new BN(40)).toString(), 'Third depositor not give LP tokens at correct ratio')
  })

  // EXIT TESTS

  async function depositToPool (amount) {
    const initialShares = await pool.balanceOf(accounts[1])
    const totalShares = await pool.totalSupply()
    const totalDeposited = await pool.totalPoolSize()
    const depositAmount = _1e18.mul(new BN(amount))
    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    const initialBalance = await weth.balanceOf(accounts[1])
    await pool.joinPool(depositAmount, { from: accounts[1] })
    const newBalance = await weth.balanceOf(accounts[1])
    assert.equal(newBalance.toString(), initialBalance.sub(depositAmount).toString(), 'Token not transfered')

    let expectedShares
    if (initialShares.toString() === '0') {
      expectedShares = _1e18.mul(new BN(100))
    } else {
      const newShares = totalShares.mul(depositAmount).div(totalDeposited)
      expectedShares = initialShares.add(newShares)
    }
    const lpwethBalance = await pool.balanceOf(accounts[1])
    assert.equal(lpwethBalance.toString(), expectedShares.toString(), 'Initial mint for first depositor was not 100')
  }

  async function checkReservedBalance (expected) {
    const expectedReservedBalance = typeof expected === 'number'
      ? _1e18.mul(new BN(expected))
      : expected
    const reservedBalance = await pool.reservedUnderlyingBalance()
    assert.equal(reservedBalance.toString(), expectedReservedBalance.toString(), 'Balance was reserved')
  }

  async function exitPoolAndCheckCompletedInstantly (amount) {
    const initialBalance = await weth.balanceOf(accounts[1])
    const lpwethUserBalanceInitial = await pool.balanceOf(accounts[1])

    const exitAmount = _1e18.mul(new BN(amount))
    pool.exitPool(exitAmount, { from: accounts[1] })

    const lpwethContractBalance = await pool.balanceOf(pool.address)
    const lpwethUserBalance = await pool.balanceOf(accounts[1])
    assert.equal(lpwethContractBalance.toString(), '0', 'LP tokens were transfered to the pool')
    assert.equal(lpwethUserBalance.toString(), lpwethUserBalanceInitial.sub(exitAmount).toString(), 'User LP tokens were not burned')

    const updatedBalance = await weth.balanceOf(accounts[1])
    assert.equal(updatedBalance.sub(initialBalance) > 0, true, 'Weth balance didnt increase')
  }

  it('exitPool: If exit is less than 20% complete in one transaction', async () => {
    await depositToPool(1000)

    await checkReservedBalance(800)

    await exitPoolAndCheckCompletedInstantly(15)

    await checkReservedBalance(800)
  })

  it('exitPool and finaliseExit: If exit is more than 20% LP tokens are destroyed and share of pool put into pending state', async () => {
    await depositToPool(1000)
    const depositAmount = _1e18.mul(new BN(1000))

    const exitAmount = _1e18.mul(new BN(80))
    pool.exitPool(exitAmount, { from: accounts[1] })

    const expectedShares = _1e18.mul(new BN(100))
    let lpwethBalance = await pool.balanceOf(accounts[1])
    assert.equal(lpwethBalance.toString(), expectedShares.sub(exitAmount).toString(), 'LP tokens not transfered away')

    let pendingExit = await pool.exitRequests(accounts[1])
    assert.equal(pendingExit.shares.toString(), exitAmount.toString())
    assert.equal(pendingExit.requestTime, await blockTime(), 'Time of request not set correctly')

    // Initialy finaliseExit will not work because time has not passed
    await pool.finaliseExit(accounts[1], { from: accounts[1] })

    pendingExit = await pool.exitRequests(accounts[1])
    assert.equal(pendingExit.shares.toString(), exitAmount.toString(), 'Pending amount has not changed')

    let updatedBalance = await weth.balanceOf(accounts[1])
    assert.equal(updatedBalance.toString(), _1e18.mul(new BN(5000)).sub(depositAmount).toString(), 'No change to weth balance')

    await moveForwardTime(86400)

    await pool.finaliseExit(accounts[1], { from: accounts[1] })

    pendingExit = await pool.exitRequests(accounts[1])
    assert.equal(pendingExit.shares, 0, 'Pending amount is not zero')

    updatedBalance = await weth.balanceOf(accounts[1])
    assert.equal(updatedBalance.toString(), _1e18.mul(new BN(4800)).toString(), 'Weth balance didnt increase')

    lpwethBalance = await pool.balanceOf(pool.address)
    assert.equal(lpwethBalance.toString(), '0', 'LP tokens not burned')
  })

  it('exitPool and finaliseExit: if insufficient funds in the pool after MAXIMUM_EXIT_PERIOD, LP tokens are destroyed and Nectar insurance funds are paid out', async () => {
    await depositToPool(20)
    const depositAmount = _1e18.mul(new BN(20))

    const exitAmount = _1e18.mul(new BN(100))
    pool.exitPool(exitAmount, { from: accounts[1] })

    // Transfer the funds out so the pool is empty
    const stakeAmount = _1e18.mul(new BN(1000000))
    await nectar.mint(accounts[0], stakeAmount)
    await nectar.approve(registry.address, stakeAmount)
    await registry.stakeNECCollateral(stakeAmount)
    await registry.transferForDeversifiWithdrawals(weth.address, accounts[8], depositAmount, getRandomSalt())

    await moveForwardTime(86400 * 2) // days

    await pool.finaliseExit(accounts[1], { from: accounts[1] })

    const pendingExit = await pool.exitRequests(accounts[1])
    assert.equal(pendingExit.shares, 0, 'Pending amount is not zero')

    const nectarBalance = await nectar.balanceOf(accounts[1])
    assert.equal(nectarBalance.toString(), _1e18.mul(new BN(50050)).toString(), 'Did not receieve any Nectar')

    const lpwethBalance = await pool.balanceOf(pool.address)
    assert.equal(lpwethBalance.toString(), '0', 'LP tokens not burned')
  })

  it('exitPool: Check that reserved balance is always respected', async () => {
    /*
      1. Enter pool
      2. Exit 10% from pool
      3. Add to the pool and see reserve increases
      4. Make transferForDeversifiWithdrawals of 50% of pool
      5. Confirm that user cannot instantly withdraw any of the pool
      6. After completion of timeout, finalise withdrawal
    */
    await depositToPool(20)
    await checkReservedBalance(16)
    await exitPoolAndCheckCompletedInstantly(10)
    await checkReservedBalance(16)
    await depositToPool(10)
    await checkReservedBalance(24)

    // Transfer the funds out so the remaining pool is less than reserved
    const stakeAmount = _1e18.mul(new BN(1000000))
    await nectar.mint(accounts[0], stakeAmount)
    await nectar.approve(registry.address, stakeAmount)
    await registry.stakeNECCollateral(stakeAmount)
    await registry.transferForDeversifiWithdrawals(weth.address, accounts[8], _1e18.mul(new BN(10)), getRandomSalt())

    const exitAmount = _1e18.mul(new BN(10))
    pool.exitPool(exitAmount, { from: accounts[1] })
    let pendingExit = await pool.exitRequests(accounts[1])
    assert.equal(pendingExit.shares.toString(), exitAmount.toString(), 'Pending amount is not 10 shares')

    await checkReservedBalance(24)
    await moveForwardTime(86400 * 2) // days

    await pool.finaliseExit(accounts[1], { from: accounts[1] })

    pendingExit = await pool.exitRequests(accounts[1])
    assert.equal(pendingExit.shares, 0, 'Pending amount is not zero')

    const totalPoolUnderlyingSize = await pool.totalPoolSize()
    await checkReservedBalance(totalPoolUnderlyingSize.mul(new BN(8)).div(new BN(10)))
  })

})

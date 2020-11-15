/* global it, contract, artifacts, assert, web3 */
const { deployProxy} = require('@openzeppelin/truffle-upgrades')

const WithdrawalPool = artifacts.require('./WithdrawalPool.sol')
const MasterTransferRegistry = artifacts.require('./MasterTransferRegistry.sol')
const MintableERC20 = artifacts.require('./MintableERC20.sol')
const MockLendingPool = artifacts.require('./MockLendingPool.sol')
const MockLendingPoolAddressesProvider = artifacts.require('./MockLendingPoolAddressesProvider.sol')

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

contract('AaveManager', (accounts) => {

  let uni, pool, weth, nectar, registry, factory, aavePool, aaveProvider

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

    aavePool = await MockLendingPool.new()
    aaveProvider = await MockLendingPoolAddressesProvider.new(aavePool.address)

    registry = await deployProxy(MasterTransferRegistry, [factory.address, weth.address, nectar.address, aaveProvider.address])
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

    await registry.setAaveIsActive(weth.address, true)
  })

  it('deploy: pool gets deployed and has Aave enabled', async () => {
    const address = await pool.poolToken()
    const aaveSetting = await registry.isAaveActive(pool.address)
    assert.equal(address, weth.address, 'Pool token not set')
    assert.equal(aaveSetting, true, 'Aave not enabled')
  })

  it('joinPool: when depositing tokens to the pool, the correct proportion is subsequently deposited into Aave', async () => {
    const depositAmount = _1e18.mul(new BN(1000))
    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[1] })
    const newBalance = await weth.balanceOf(accounts[1])
    assert.equal(newBalance.toString(), _1e18.mul(new BN(5000)).sub(depositAmount).toString(), 'Token not transfered')

    // To check:
    // Lending Pool WETH balance is 200
    // Lending Pool AToken balance is 800
    const lendingPoolWETHBalance = await weth.balanceOf(pool.address)
    const lendingPoolATokenBalance = await aavePool.balanceOf(pool.address)

    assert.equal(lendingPoolWETHBalance.toString(), _1e18.mul(new BN(200)).toString(), 'WETH not in correct ratio')
    assert.equal(lendingPoolATokenBalance.toString(), _1e18.mul(new BN(800)).toString(), 'AToken not in correct ratio')
  })

  it('joinPool: on the first deposit after aave being enabled, the full amount to achieve the target ratio is deposited', async () => {
    await registry.setAaveIsActive(weth.address, false)
    const depositAmount = _1e18.mul(new BN(1000))
    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[1] })

    await registry.setAaveIsActive(weth.address, true)

    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[1] })

    // To check:
    // Lending Pool WETH balance is 400
    // Lending Pool AToken balance is 1600
    const lendingPoolWETHBalance = await weth.balanceOf(pool.address)
    const lendingPoolATokenBalance = await aavePool.balanceOf(pool.address)

    assert.equal(lendingPoolWETHBalance.toString(), _1e18.mul(new BN(400)).toString(), 'WETH not in correct ratio')
    assert.equal(lendingPoolATokenBalance.toString(), _1e18.mul(new BN(1600)).toString(), 'AToken not in correct ratio')
  })

  it('transferForDeversifiWithdrawals: when transfering out more WETH than currently liquid, the required amount is withdrawn from Aave', async () => {
    const depositAmount = _1e18.mul(new BN(100))
    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[1] })

    const stakeAmount = _1e18.mul(new BN(1000000000))
    await nectar.mint(accounts[0], stakeAmount)
    await nectar.approve(registry.address, stakeAmount)
    await registry.stakeNECCollateral(stakeAmount)

    const transferAmount = _1e18.mul(new BN(35))
    await registry.transferForDeversifiWithdrawals(weth.address, accounts[5], transferAmount, getRandomSalt())

    const recipientWETHBalance = await weth.balanceOf(accounts[5])
    const lendingPoolWETHBalance = await weth.balanceOf(pool.address)
    const lendingPoolATokenBalance = await aavePool.balanceOf(pool.address)

    const transferAmountAfterFee = transferAmount.mul(new BN(999)).div(new BN(1000))

    assert.equal(recipientWETHBalance.toString(), transferAmountAfterFee.toString(), 'WETH not received by recipient')
    assert.equal(lendingPoolWETHBalance.toString(), depositAmount.sub(transferAmountAfterFee).mul(new BN(20)).div(new BN(100)).toString(), 'WETH not in correct ratio')
    assert.equal(lendingPoolATokenBalance.toString(), depositAmount.sub(transferAmountAfterFee).mul(new BN(80)).div(new BN(100)).toString(), 'AToken not in correct ratio')
  })

  it('transferForDeversifiWithdrawals: after Aave is enabled for a pool, transfering out WETH does not require a withdrawal from aave', async () => {
    await registry.setAaveIsActive(weth.address, false)

    const depositAmount = _1e18.mul(new BN(100))
    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[1] })

    const stakeAmount = _1e18.mul(new BN(1000000000))
    await nectar.mint(accounts[0], stakeAmount)
    await nectar.approve(registry.address, stakeAmount)
    await registry.stakeNECCollateral(stakeAmount)

    await registry.setAaveIsActive(weth.address, true)

    const transferAmount = _1e18.mul(new BN(35))
    await registry.transferForDeversifiWithdrawals(weth.address, accounts[5], transferAmount, getRandomSalt())

    const recipientWETHBalance = await weth.balanceOf(accounts[5])
    const lendingPoolWETHBalance = await weth.balanceOf(pool.address)
    const lendingPoolATokenBalance = await aavePool.balanceOf(pool.address)

    const transferAmountAfterFee = transferAmount.mul(new BN(999)).div(new BN(1000))

    assert.equal(recipientWETHBalance.toString(), transferAmountAfterFee.toString(), 'WETH not received by recipient')
    assert.equal(lendingPoolWETHBalance.toString(), depositAmount.sub(transferAmountAfterFee).toString(), 'WETH not in correct ratio')
    assert.equal(lendingPoolATokenBalance.toString(), '0', 'AToken not in correct ratio')
  })

})

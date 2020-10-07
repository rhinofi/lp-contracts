/* global it, contract, artifacts, assert, web3 */
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

function assertEventOfType (response, eventName, index) {
  assert.equal(response.logs[index].event, eventName, eventName + ' event should have fired.')
}

function getRandomSalt () {
  return Math.floor(Math.random() * Math.floor(10000000))
}

const catchRevert = require('./helpers/exceptions').catchRevert
const moveForwardTime = require('./helpers/utils').moveForwardTime
const BN = web3.utils.BN
const _1e18 = new BN('1000000000000000000')

contract('MasterTransferRegistry', (accounts) => {

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

    registry = await MasterTransferRegistry.new(factory.address, weth.address, nectar.address)
    await registry.createNewPool(weth.address)
    await weth.mint(accounts[1], _1e18.mul(new BN(5000)))
    const poolAddress = await registry.tokenPools(weth.address)
    pool = await WithdrawalPool.at(poolAddress)

    const depositAmount = _1e18.mul(new BN(1000))
    await weth.approve(pool.address, depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[1] })

    await moveForwardTime(86400)
    await weth.transfer(uni.address, _1e18.mul(new BN(4)))
    await nectar.transfer(uni.address, _1e18.mul(new BN(5000)))
    await uni.mint(accounts[0], { from: accounts[0] })

    await registry.updateExchangeRate(nectar.address)
    const price = await registry.necExchangeRate(weth.address, _1e18)
    const expectedRatio = new BN(1250)
    assert.equal(price.toString(), _1e18.mul(expectedRatio).toString(), 'Price was not updated')
  })

  it('deploy: transfer registry gets deployed and has correct identifier', async () => {
    const name = await registry.identify()
    assert.equal(name, 'DeversiFi_MasterTransferRegistry_v0.0.1', 'Name not set')
  })

  it('transferERC20: cannot transfer more than deposited in the weth pool', async () => {
    const transferAmount = _1e18.mul(new BN(1001))
    await catchRevert(registry.transferERC20(weth.address, accounts[5], transferAmount, getRandomSalt()))
  })

  it('transferERC20: cannot transfer if no NEC staked', async () => {
    const transferAmount = _1e18.mul(new BN(500))
    await catchRevert(registry.transferERC20(weth.address, accounts[5], transferAmount, getRandomSalt()))
  })

  it('transferERC20: can transfer weth from pool if NEC staked and below available limit', async () => {
    const stakeAmount = _1e18.mul(new BN(1000000))
    await nectar.mint(accounts[0], stakeAmount)
    await nectar.approve(registry.address, stakeAmount)
    await registry.stakeNECCollateral(stakeAmount)

    const transferAmount = _1e18.mul(new BN(5))
    await registry.transferERC20(weth.address, accounts[5], transferAmount, getRandomSalt())
  })

})

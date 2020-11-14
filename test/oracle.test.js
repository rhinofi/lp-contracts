/* global it, contract, artifacts, assert, web3 */
const { deployProxy } = require('@openzeppelin/truffle-upgrades')

const MasterTransferRegistry = artifacts.require('./MasterTransferRegistry.sol')
const MintableERC20 = artifacts.require('./MintableERC20.sol')
const factoryJson = require('@uniswap/v2-core/build/UniswapV2Factory.json')
const pairJson = require('@uniswap/v2-core/build/UniswapV2Pair.json')
const contractInit = require('@truffle/contract')
const UniswapV2Factory = contractInit(factoryJson)
const UniswapV2Pair = contractInit(pairJson)
UniswapV2Factory.setProvider(web3.currentProvider)
UniswapV2Pair.setProvider(web3.currentProvider)

const catchRevert = require('./helpers/exceptions').catchRevert
const { moveForwardTime, assertEventOfType } = require('./helpers/utils')

const BN = web3.utils.BN
const _1e18 = new BN('1000000000000000000')

contract('OracleManager', (accounts) => {

  let weth, nectar, factory, oracle, pool

  beforeEach(async function () {
    weth = await MintableERC20.new('Wrapped_ETH', 'WETH')
    nectar = await MintableERC20.new('Nectar', 'NEC')
    factory = await UniswapV2Factory.new(accounts[0], { from: accounts[0] })

    const tx = await factory.createPair(weth.address, nectar.address, { from: accounts[0] })
    assertEventOfType(tx, 'PairCreated', 0)
    pool = await UniswapV2Pair.at(tx.logs[0].args.pair)

    await weth.mint(accounts[0], _1e18.mul(new BN(100)))
    await nectar.mint(accounts[0], _1e18.mul(new BN(200000)))
    await weth.transfer(pool.address, _1e18.mul(new BN(40)))
    await nectar.transfer(pool.address, _1e18.mul(new BN(50000)))
    await pool.mint(accounts[0], { from: accounts[0] })

    oracle = await deployProxy(MasterTransferRegistry, [factory.address, weth.address, nectar.address, accounts[9]])
  })

  it('deploy: oracle manager and uniswap pair get deployed', async () => {
    const address = await oracle.uniswapFactory()
    assert.equal(address, factory.address, 'Contract not properly deployed')
    const token0 = await pool.token0()
    assert.equal(token0, weth.address, 'Pool not created')
  })

  it('deploy: oracle manager and uniswap pair get deployed and has liquidity in it', async () => {
    const address = await oracle.uniswapFactory()
    assert.equal(address, factory.address, 'Contract not properly deployed')
    const token0 = await pool.token0()
    const token1 = await pool.token1()
    const reserves = await pool.getReserves()
    try {
      assert.equal(token0, weth.address, 'Pool not created')
      const priceRatio = reserves._reserve1.div(reserves._reserve0)
      assert.equal(priceRatio.toString(), 1250, 'Reserve ratio not correct')
    } catch (err) {
      assert.equal(token1, weth.address, 'Pool not created')
      const priceRatio = reserves._reserve0.div(reserves._reserve1)
      assert.equal(priceRatio.toString(), 1250, 'Reserve ratio not correct')
    }
  })

  it('registerNewOracle: oracle manager tracks new uniswap pair for USDT/WETH', async () => {
    // NEC/WETH should already be tracked
    const necWethPair = await oracle.uniswapPairs(nectar.address)
    assert.equal(necWethPair, pool.address, 'Pair was not registered at deployment or oracle manager')

    const tether = await MintableERC20.new('Tether_USD', 'USDT')

    const tx = await factory.createPair(tether.address, weth.address, { from: accounts[0] })
    assertEventOfType(tx, 'PairCreated', 0)
    pool = await UniswapV2Pair.at(tx.logs[0].args.pair)

    await tether.mint(accounts[0], _1e18.mul(new BN(100000)))
    await tether.transfer(pool.address, _1e18.mul(new BN(10000)))
    await weth.transfer(pool.address, _1e18.mul(new BN(40)))
    await pool.mint(accounts[0], { from: accounts[0] })

    await oracle.registerNewOracle(tether.address)

    const usdtEthPair = await oracle.uniswapPairs(tether.address)
    assert.equal(usdtEthPair, pool.address, 'Pair was not registered')
  })

  it('necExchangeRate: throws if there are no prices yet', async () => {
    await catchRevert(oracle.necExchangeRate(weth.address, 100))
  })

  it('updateExchangeRate: returns correct price for WETH to NEC after update', async () => {
    // There needs to be some history on uniswap in order for it to give prices
    // So here we wait a few blocks and then add more liquidity
    await moveForwardTime(86400)

    await weth.transfer(pool.address, _1e18.mul(new BN(4)))
    await nectar.transfer(pool.address, _1e18.mul(new BN(5000)))
    await pool.mint(accounts[0], { from: accounts[0] })

    await oracle.updateExchangeRate(nectar.address)
    const price = await oracle.necExchangeRate(weth.address, _1e18)
    const expectedRatio = new BN(1250)
    assert.equal(price.toString(), _1e18.mul(expectedRatio).toString(), 'Price was not updated')
  })

  it('updateExchangeRate: returns correct price for USDT to NEC after update', async () => {

    const tether = await MintableERC20.new('Tether_USD', 'USDT')

    const tx = await factory.createPair(tether.address, weth.address, { from: accounts[0] })
    assertEventOfType(tx, 'PairCreated', 0)
    const poolTether = await UniswapV2Pair.at(tx.logs[0].args.pair)

    await tether.mint(accounts[0], _1e18.mul(new BN(100000)))
    await tether.transfer(poolTether.address, _1e18.mul(new BN(10000)))
    await weth.transfer(poolTether.address, _1e18.mul(new BN(40)))
    await poolTether.mint(accounts[0], { from: accounts[0] })

    await oracle.registerNewOracle(tether.address)

    const usdtEthPair = await oracle.uniswapPairs(tether.address)
    assert.equal(usdtEthPair, poolTether.address, 'Pair was not registered')

    await moveForwardTime(86400)

    await tether.transfer(poolTether.address, _1e18.mul(new BN(1000)))
    await weth.transfer(poolTether.address, _1e18.mul(new BN(4)))
    await poolTether.mint(accounts[0], { from: accounts[0] })

    await weth.transfer(pool.address, _1e18.mul(new BN(4)))
    await nectar.transfer(pool.address, _1e18.mul(new BN(5000)))
    await pool.mint(accounts[0], { from: accounts[0] })

    await oracle.updateExchangeRate(tether.address)
    await oracle.updateExchangeRate(nectar.address)
    const price = await oracle.necExchangeRate(tether.address, _1e18)
    const expectedRatio = new BN(5)
    // Note there can be rounding here so we check for almost equal
    const expectedPrice = _1e18.mul(expectedRatio)
    assert.isTrue(price.sub(expectedPrice).abs().toNumber() < 2000, 'Price was not close to expected')
  })

})

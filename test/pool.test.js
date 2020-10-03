/* global it, contract, artifacts, assert, web3 */
const WithdrawalPool = artifacts.require('./WithdrawalPool.sol')
const MasterTransferRegistry = artifacts.require('./MasterTransferRegistry.sol')
const MintableERC20 = artifacts.require('./MintableERC20.sol')
// const UniswapV2Factory = artifacts.require('./UniswapV2Factory.sol')

const catchRevert = require("./helpers/exceptions").catchRevert
const BN = web3.utils.BN
const _1e18 = new BN('1000000000000000000')

contract('WithdrawalPool', (accounts) => {

  let pool, token, nectar, registry

  beforeEach('redeploy contract', async function () {
    token = await MintableERC20.new('Tether_USD', 'USDT')
    nectar = await MintableERC20.new('Nectar', 'NEC')
    registry = await MasterTransferRegistry.new(accounts[9], token.address, nectar.address)
    await registry.createNewPool(token.address)
    await token.mint(accounts[1], _1e18.mul(new BN(5000)))
    const poolAddress = await registry.tokenPools(token.address)
    pool = await WithdrawalPool.at(poolAddress)
  })

  it('deploy: pool gets deployed and has correct pool token address', async () => {
    const address = await pool.poolToken()
    const masterRegistry = await pool.transferRegistry()
    const totalPoolSize = await pool.totalPoolSize()
    assert.equal(address, token.address, 'Pool token not set')
    assert.equal(masterRegistry, registry.address, 'Master not correctly set in pool contract')
    assert.equal(totalPoolSize, 0, 'There are already deposits?')
  })

  it('joinPool: when depositing tokens to the pool, the tokens are transfered into the contract, and correct number of LP tokens are minted for depositor', async () => {
    const depositAmount = _1e18.mul(new BN(1000))
    await token.approve(pool.address, depositAmount, { from: accounts[1] })
    await pool.joinPool(depositAmount, { from: accounts[1] })
    const newBalance = await token.balanceOf(accounts[1])
    assert.equal(newBalance.toString(), _1e18.mul(new BN(5000)).sub(depositAmount).toString(), 'Token not transfered')

    const lpTokenBalance = await pool.balanceOf(accounts[1])
    assert.equal(lpTokenBalance.toString(), _1e18.mul(new BN(100)).toString(), 'Initial mint for first depositor was not 100')
  })

  it('joinPool: multiple depositors get credited correct ratio of LP tokens', async () => {
    const depositAmount = _1e18.mul(new BN(1000))
    await token.transfer(accounts[2], depositAmount, { from: accounts[1] })
    await token.transfer(accounts[3], _1e18.mul(new BN(400)), { from: accounts[1] })
    await token.approve(pool.address, depositAmount, { from: accounts[1] })
    await token.approve(pool.address, depositAmount, { from: accounts[2] })
    await token.approve(pool.address, depositAmount, { from: accounts[3] })

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

  it('exitPool: LP tokens are destroyed and proportional share of pool withdrawn', async () => {

  })

})

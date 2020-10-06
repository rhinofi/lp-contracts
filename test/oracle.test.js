/* global it, contract, artifacts, assert, web3 */
const OracleManager = artifacts.require('./OracleManager.sol')
const MintableERC20 = artifacts.require('./MintableERC20.sol')
const contractJson = require('@uniswap/v2-core/build/UniswapV2Factory.json')
const contractInit = require('@truffle/contract')
const UniswapV2Factory = contractInit(contractJson)
UniswapV2Factory.setProvider(web3.currentProvider)

const catchRevert = require("./helpers/exceptions").catchRevert

contract('OracleManager', (accounts) => {

  let token, nectar, factory, oracle

  beforeEach(async function () {
    token = await MintableERC20.new('Tether_USD', 'USDT')
    nectar = await MintableERC20.new('Nectar', 'NEC')
    factory = await UniswapV2Factory.new(accounts[0], { from: accounts[0] })
    oracle = await OracleManager.new(factory.address, token.address, nectar.address)
  })

  it('deploy: oracle manager gets deployed', async () => {
    const address = await oracle.uniswapFactory()
    assert.equal(address, factory.address, 'Contract not properly deployed')
  })
})

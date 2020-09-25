/* global it, contract, artifacts, assert, web3 */
const WithdrawalPoolTransferRegistry = artifacts.require('./WithdrawalPoolTransferRegistry.sol')
const ERC20 = artifacts.require('./ERC20.sol')

const catchRevert = require("./helpers/exceptions").catchRevert

contract('WithdrawalPoolTransferRegistry', (accounts) => {

  let pool, token, nectar

  beforeEach('redeploy contract', async function () {
    token = await ERC20.new('Tether_USD', 'USDT')
    nectar = await ERC20.new('Nectar', 'NEC')
    pool = await WithdrawalPoolTransferRegistry.new('Tether_USD', 'USDT', token.address, nectar.address, nectar.address)
  })

  it('pool gets deployed and has an identifier', async () => {
    const name = await pool.identify()
    assert.equal(name, 'DeversiFi_WithdrawalPoolRegistry_v0.0.1_Tether_USD', 'Identifier not set')
  })
})

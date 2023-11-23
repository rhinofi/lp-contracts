const { deployProxy } = require('@openzeppelin/truffle-upgrades')

const TransferRegistry = artifacts.require('TransferRegistry')

module.exports = async function (deployer) {
  if (deployer.network !== 'goerli') {
    return
  }
  const registryInstance = await deployProxy(TransferRegistry, [], { deployer })
  console.log('Deployed Registry', registryInstance.address)
}

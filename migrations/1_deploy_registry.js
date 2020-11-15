const { deployProxy } = require('@openzeppelin/truffle-upgrades')

const MasterTransferRegistry = artifacts.require('MasterTransferRegistry')

module.exports = async function (deployer) {
  if (deployer.network !== 'kovan') {
    return
  }
  const uniswapFactory = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f'
  const wethAddress = '0xd0a1e359811322d97991e03f863a0c30c2cf029c'
  const nectarAddress = '0x68cee0bbfe45e5ac0d6c34f19e57204094d4658a'
  const aaveRegistry = '0x652B2937Efd0B5beA1c8d54293FC1289672AFC6b'
  const registryInstance = await deployProxy(MasterTransferRegistry, [uniswapFactory, wethAddress, nectarAddress, aaveRegistry], { deployer })
  console.log('Deployed Registry', registryInstance.address)
}

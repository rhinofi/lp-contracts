const { deployProxy } = require('@openzeppelin/truffle-upgrades')

const MasterTransferRegistry = artifacts.require('MasterTransferRegistry')

module.exports = async function (deployer) {
  if (deployer.network !== 'rinkeby') {
    return
  }
  const uniswapFactory = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f'
  const wethAddress = '0xc778417E063141139Fce010982780140Aa0cD5Ab'
  const nectarAddress = '0x5dc480718DEBF5ED304C835EB14448A4810c06A6'
  const registryInstance = await deployProxy(MasterTransferRegistry, [uniswapFactory, wethAddress, nectarAddress], { deployer })
  console.log('Deployed Registry', registryInstance.address)
}

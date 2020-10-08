function logGasUsage (subject, transactionOrReceipt) {
  const receipt = transactionOrReceipt.receipt || transactionOrReceipt
  console.log('    Gas costs for ' + subject + ': ' + receipt.gasUsed)
}

async function blockTime () {
  const block = await web3.eth.getBlock('latest')
  return block.timestamp
}

async function snapshot () {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_snapshot',
      id: Date.now()
    }, (err, res) => {
      return err ? reject(err) : resolve(res)
    })
  })
}

async function restore (snapshot) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_revert',
      params: [snapshot.result],
      id: snapshot.id
    }, (err, res) => {
      return err ? reject(err) : resolve(res)
    })
  })
}

async function forceMine () {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_mine',
      id: Date.now()
    }, (err, res) => {
      return err ? reject(err) : resolve(res)
    })
  })
}

async function timeJump (time) {
  return new Promise((resolve, reject) => {
    // const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:9545')) // Hardcoded development port
    // console.log(web3.currentProvider)
    web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_increaseTime',
      params: [time], // 86400 is num seconds in day
      id: new Date().getTime()
    }, (err, result) => {
      if (err) { return reject(err) }
      return resolve(result)
    })
  })
}

async function moveForwardTime (time) {
  await timeJump(time)
  await forceMine()
  await blockTime()
  return true
}

function assertEventOfType (response, eventName, index) {
  assert.equal(response.logs[index].event, eventName, eventName + ' event should have fired.')
}

function getRandomSalt () {
  return Math.floor(Math.random() * Math.floor(10000000))
}

module.exports = {
  logGasUsage,
  blockTime,
  snapshot,
  restore,
  forceMine,
  moveForwardTime,
  assertEventOfType,
  getRandomSalt
}

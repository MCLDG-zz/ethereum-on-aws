const Web3 = require('web3')
const aws = require('aws-sdk')

exports.handler = (event, context, callback) => {
  executeTransaction(context)
}

async function executeTransaction (context) {
  const s3 = new aws.S3()
  const dynamodb = new aws.DynamoDB({region: 'us-east-1'})

  var params = {
    Key: {
      'key': {
        S: 'ContractAddress'
      }
    },
    TableName: 'blockchainblog'
  }

  const response = await dynamodb.getItem(params).promise()

  console.log(response['Item']['address']['S'])
  const contractAddress = response['Item']['address']['S']

  console.log('Executing Transactions')

  // connect to the blockchain
  const blockchain = process.env.BLOCKCHAIN_HOST
  const web3 = new Web3(new Web3.providers.HttpProvider('http://' + blockchain + ':8545'))


  // The Contract ABI
  var abiDefinition = JSON.parse('[{"constant":false,"inputs":[],"name":"bid","outputs":[{"name":"bid_made","type":"bool"}],"payable":true,"stateMutability":"payable","type":"function"},{"constant":false,"inputs":[],"name":"withdraw","outputs":[{"name":"done","type":"bool"}],"payable":true,"stateMutability":"payable","type":"function"},{"payable":true,"stateMutability":"payable","type":"fallback"},{"anonymous":false,"inputs":[{"indexed":true,"name":"_bidder","type":"address"},{"indexed":false,"name":"amount","type":"uint256"},{"indexed":false,"name":"max_bidder","type":"address"},{"indexed":false,"name":"contract_creator","type":"address"}],"name":"BidEvent","type":"event"}]')

  const contract = new web3.eth.Contract(abiDefinition, contractAddress)
  const currentBlock = await web3.eth.getBlockNumber()

  const blockParams = {
    Key: {
      'key': {
        S: 'StartBlock'
      }
    },
    TableName: 'blockchainblog'
  }

  const startBlockResponse = await dynamodb.getItem(blockParams).promise()
  const startBlock = startBlockResponse['Item']['value']['N']

  console.log('StartBlock: ' + startBlock)
  const accountsParams = {
    Bucket: 'blockchainblog', 
    Key: 'accounts.json'
  }

  var accountsRequest = await s3.getObject(accountsParams).promise()
  const accounts = JSON.parse(accountsRequest.Body.toString('utf-8'))

  for (var i = 0; i < 10; i++) {
    if (currentBlock > startBlock + 1000) {
      await generateRawTransaction(contract, accounts, web3, false)
    } else {
      await generateRawTransaction(contract, accounts, web3, true)
    }
  }
}

async function generateRawTransaction (contract, accounts, web3, bid) {
  const account = accounts[getRandomInt(0, 9)]
  const from = account.account

  const data = bid
      ? contract.methods.bid().encodeABI()
      : contract.methods.withdraw().encodeABI()

  const tx = {
    // chainId: 15,
    //nonce: await web3.utils.toHex(await web3.eth.getTransactionCount(from)),
    from: from,
    gas: 4612388,
    value: web3.utils.toHex(getRandomInt(1 + 1, 1 + 10)),
    to: contract._address,
    data: contract.methods.bid().encodeABI()
  }

  const signedTx = await web3.eth.accounts.signTransaction(tx, '0x' + account.key)
  const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction)
  console.log(signedTx)
}

function getRandomInt (min, max) {
  min = Math.ceil(min)
  max = Math.floor(max)
  return Math.floor(Math.random() * (max - min)) + min
}


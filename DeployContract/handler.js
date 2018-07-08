var Web3 = require('web3')
var solc = require('solc')
var aws = require('aws-sdk')

var s3 = new aws.S3()
var dynamodb = new aws.DynamoDB({
  region: 'us-east-1'
})

exports.handler = (event, context, callback) => {
  var result = deployContract(context)
  return result
}

async function deployContract (context) {
  console.log('fetching contract from S3')

  var params = {
    Bucket: 'blockchainblog',
    Key: 'Auction.sol'
  }

  const getContract = await s3.getObject(params).promise()
  const contract = getContract.Body.toString('utf-8')

  console.log('Deploying Contract')

  // compilation, we read in the Solidity file and compile
  var compiledCode = solc.compile(contract)

  // connect to the blockchain
  var blockchain = process.env.BLOCKCHAIN_HOST

  var web3 = new Web3(new Web3.providers.HttpProvider('http://' + blockchain + ':8545'))

  // Get the Bytecode
  var byteCode = compiledCode.contracts[':auction'].bytecode

  const contractOwner = '0x34db0A1D7FE9D482C389b191e703Bf0182E0baE3'
  const privateKey = '0x403cf58c6a36eee43ac8467bec2c9d65d8dc92aee461debffb4acff277548ef3'

  const tx = {
    chainId: 15,
    nonce: await web3.utils.toHex(await web3.eth.getTransactionCount(contractOwner)),
    gas: 4612388,
    from: contractOwner,
    data: byteCode
  }

  console.log(tx)

  const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey)
  const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction)

  console.log(receipt.contractAddress)

  const putContractAddressParams = {
    Item: {
      'key': {
        S: 'ContractAddress'
      },
      'address': {
        S: receipt.contractAddress
      }
    },
    ReturnConsumedCapacity: 'TOTAL',
    TableName: 'blockchainblog'
  }

  console.log('Writing Contract Address to Dynamo')
  const putContractAdddresResponse = await dynamodb.putItem(putContractAddressParams).promise()
  const blockNumber = await web3.eth.getBlockNumber()

  const putStartBlockParams = {
    Item: {
      'key': {
        S: 'StartBlock'
      },
      'value': {
        N: blockNumber.toString()
      }
    },
    ReturnConsumedCapacity: 'TOTAL',
    TableName: 'blockchainblog'
  }

  console.log('Writing Block Number to Dynamo')
  const putBlockNumberResponse = await dynamodb.putItem(putStartBlockParams).promise()

  context.done(null, 'contract deployed') // SUCCESS with message
}


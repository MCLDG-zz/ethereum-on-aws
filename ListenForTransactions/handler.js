const Web3 = require('web3');
const aws = require('aws-sdk');

const ec2 = new aws.EC2({
  region: 'us-east-1'
});
const dynamodb = new aws.DynamoDB({
  region: 'us-east-1'
});
const kinesis = new aws.Kinesis({
  apiVersion: '2013-12-02',
  region: 'us-east-1'
});

exports.handler = (event, context, callback) => {
}


function writeBlockNumber(blockNumber) {
  var params = {
    Item: {
      "key": {
        S: "LastEventBlock"
      },
      "value": {
        N: block
      }
    },
    ReturnConsumedCapacity: "TOTAL",
    TableName: "blockchainblog"
  };
  dynamodb.putItem(params, function(err, data) {
    if (err) {
      console.log(err, err.stack); // an error occurred
    }
  });
}


async function getLastBlock(){

  var params = {
    Key: {
      "key": {
        S: "LastEventBlock"
      }
    },
    TableName: "blockchainblog"
  };

var lastBlock = 0
  const lastBlockReponse = await dynamodb.getItem(params).promise()

      try {
          lastBlock = data["Item"]["value"]['N'];
      } catch(err) {
          lastBlock = 0;
      }
      console.log("Last block events were fetched from was: " + lastBlock);
return lastBlock
}



async function listenForEvents(){
  // connect to the blockchain
  var blockchain = process.env.BLOCKCHAIN_HOST
  var web3 = new Web3('ws://' + blockchain + ':8546')


  console.log("Getting contract address from dynamo")
  var params = {
    Key: {
      "key": {
        S: "ContractAddress"
      }  
    },
    TableName: "blockchainblog"
  }


  const contractResponse = await dynamodb.getItem(params).promise()
  const abi = JSON.parse('[{"constant":false,"inputs":[],"name":"bid","outputs":[{"name":"bid_made","type":"bool"}],"payable":true,"stateMutability":"payable","type":"function"},{"constant":false,"inputs":[],"name":"withdraw","outputs":[{"name":"done","type":"bool"}],"payable":true,"stateMutability":"payable","type":"function"},{"payable":true,"stateMutability":"payable","type":"fallback"},{"anonymous":false,"inputs":[{"indexed":true,"name":"_bidder","type":"address"},{"indexed":false,"name":"amount","type":"uint256"},{"indexed":false,"name":"max_bidder","type":"address"},{"indexed":false,"name":"contract_creator","type":"address"}],"name":"BidEvent","type":"event"}]');

  const contractAddress = contractResponse["Item"]["address"]['S'];
  console.log("Using Contract: " + contractAddress);
  const contract = new web3.eth.Contract(abi, contractAddress);

  const lastBlock = await getLastBlock()

  contract.events.BidEvent({
    fromBlock: lastBlock + 1
  }, function(error, blockchainEvent) {
    console.log(blockchainEvent)
    innerEvent = blockchainEvent["returnValues"];
    record = {
      "Block": blockchainEvent["blockNumber"],
      "BlockHash": blockchainEvent["transactionHash"],
      "Bidder": innerEvent._bidder,
      "MaxBidder": innerEvent.max_bidder,
      "ContractOwner": innerEvent.contract_creator,
      "Amount": innerEvent.amount,
      "Auction": contractAddress,
      "EventTimestamp": new Date().getTime()
    }

    console.log(JSON.stringify(record));

    var params = {
      Data: JSON.stringify(record) + "\n",
      PartitionKey: record["Bidder"],
      StreamName: 'blockchainblog'
    };

    kinesis.putRecord(params, function(err, data) {
      if (err) console.log(err, err.stack); // an error occurred
      else console.log(data); // successful response
    });


    block = event["blockNumber"].toString();
    writeBlockNumber(block);
  });
}



pragma solidity ^0.4.19;

contract auction {
    mapping (address => uint) bids;
    uint max_bid = 0;
    address max_bidder;
    address creator = msg.sender;
    uint finish_block_id = block.number + 10000;


    event BidEvent(
        address indexed _bidder,
        uint256 amount,
        address max_bidder,
        address contract_creator
    );

    function bid() payable public returns (bool bid_made) {
        if (block.number >= finish_block_id) {
            return withdraw();
        }

        bids[msg.sender] += msg.value;

        if (bids[msg.sender] > max_bid) {
            max_bid = bids[msg.sender];
            max_bidder = msg.sender;
        }

        BidEvent(msg.sender, msg.value, max_bidder, creator);

        return true;
    }

    function withdraw() payable public returns (bool done) {
        uint payout = msg.value;

        // Only allow payouts after the auction has finished
        if (block.number < finish_block_id) {
            msg.sender.transfer(payout);
            return false;
        }

        // The seller can withdraw the winning bid
        if (msg.sender == creator) {
            payout += max_bid;
            max_bid = 0;
        }

        // Users who didn't win can get their funds back
        if (msg.sender != max_bidder) {
            payout += bids[msg.sender];
            bids[msg.sender] = 0;
        }

        msg.sender.transfer(payout);
        return true;
    }

    function() payable public{
        msg.sender.transfer(msg.value);
    }
}


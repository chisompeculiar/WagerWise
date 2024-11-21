# WagerWise: Prediction Market Smart Contract

## Overview
WagerWise is a Stacks blockchain smart contract that enables the creation and management of decentralized prediction markets. Users can create markets, place bets, and claim winnings based on market outcomes.

## Features
- Create prediction markets with multiple options
- Place bets on market outcomes
- Settle markets with a designated winning option
- Claim winnings for successful predictions

## Contract Functions

### Market Creation
- `create-market`: Allows users to create a new prediction market
  - Parameters:
    - `description`: Market description (up to 256 UTF-8 characters)
    - `options`: List of prediction options (1-10 options)
    - `end-block`: Block height when the market closes

### Betting
- `place-bet`: Users can place bets on a specific market option
  - Parameters:
    - `market-id`: Unique identifier of the market
    - `option`: Selected prediction option
    - `amount`: Bet amount in STX

### Market Settlement
- `settle-market`: Market creator can declare the winning option
  - Can only be called after the market end block
  - Only callable by the market creator

### Winnings Claim
- `claim-winnings`: Allows users to claim winnings for correct predictions

## Read-Only Functions
- `get-market`: Retrieve details of a specific market
- `get-bet`: Get bet details for a specific user and market

## Error Handling
The contract includes comprehensive error handling:
- `ERR-NOT-FOUND`: Market or bet not found
- `ERR-UNAUTHORIZED`: Unauthorized action
- `ERR-ALREADY-SETTLED`: Market already settled
- `ERR-MARKET-ACTIVE`: Market is still active
- `ERR-INVALID-INPUT`: Invalid input parameters

## Security Checks
- Validates market creation inputs
- Ensures bets are placed before market end
- Prevents duplicate settlements
- Restricts winnings claims to correct predictions

## Requirements
- Stacks blockchain
- Compatible Stacks wallet

## Potential Improvements
- Add fee mechanism for market creators
- Implement more complex payout calculations
- Add support for more diverse market types


## Contributing
Contributions are welcome. Please submit pull requests or open issues on the project repository.
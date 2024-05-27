# Proveably Random Raffle Contracts

## About

This project creates a proveably random smart contract lottery.

## Functionality

1. Users enter the lottery by paying for a ticket.
    1. Total ticket fees collected will go to the winner of the lottery.
2. After X period of time, the lottery will automatically pick a winner.
    1. This will be done programatically.
3. Using Chainlink VRF and Chainlink Automation.
    1. Chainlink VRF - proveable randomness
    2. Chainlink Automation - time-based trigger

## Requirements

To compile and run this code, you will need:
[git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git), and
[foundry](https://getfoundry.sh/)

## Libraries Required

```
forge install foundry-rs/forge-std --no-commit
forge install smartcontractkit/chainlink-brownie-contracts --no-commit

```
## Quickstart

Clone to your local repo and build.
```
git clone https://github.com/saracen75/foundry-smart-contract-lottery-f23
cd foundry-smart-contract-lottery-f23
forge build
```
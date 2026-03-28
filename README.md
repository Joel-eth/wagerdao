# WagerDAO

> Trustless peer-to-peer sports betting on Base.
> No bookmaker. No custody. No KYC maze. Just code, markets, and USDC.

WagerDAO is being built as an onchain sports betting protocol where users bet against each other instead of against a house. Markets are created for real matches, bets are placed in USDC, outcomes are resolved onchain, and winners claim from the pool automatically.

This repo is the build log and source of truth for that protocol.

## What WagerDAO Is

Traditional sportsbooks control the odds, hold the money, and keep the edge.

WagerDAO flips that model:

- Bettors face other bettors, not a centralized bookmaker
- Funds live in smart contracts, not in an offchain account
- Payouts are determined by market pools
- Protocol fees are transparent and enforced onchain
- The full system is open source and verifiable

The goal is simple: make sports betting feel like crypto should have built it in the first place.

## The Core Idea

A market is created for a match.
Users choose an outcome.
USDC is deposited into the contract.
When the event finishes, the market is resolved.
Winning bettors claim their share of the pool.

WagerDAO is designed around a parimutuel model:

- More money on one side lowers the implied payout for that side
- Less money on the other side increases the upside if that side wins
- The protocol takes a fee only on profit, not on the original stake

## Why Base

WagerDAO is being built on Base because the product needs:

- Low fees so small bets still make sense
- Fast confirmations so the betting flow feels usable
- EVM compatibility for straightforward smart contract tooling
- A growing retail user base already familiar with onchain apps

USDC on Base is the settlement asset because it keeps the experience stable and understandable.

## Current Status

This repository is in active build mode.

What exists right now:

- Hardhat project setup
- Base and Base Sepolia network configuration
- Environment template for deployment and frontend variables
- Initial WagerDAO contract skeleton with:
  - protocol constants
  - market and bet data structures
  - enums for market state and outcomes
  - event definitions
  - custom errors
  - immutable fee wallet and USDC configuration

What is not implemented yet:

- market creation logic
- bet placement logic
- locking, resolution, and payouts
- tests
- deployment scripts
- frontend
- automation

That means this repo is early, but the architecture direction is already locked in.

## Planned User Flow

1. A market is created for a match
2. Bettors place USDC on HOME, AWAY, or DRAW
3. The market locks at kickoff
4. The result is resolved after the event finishes
5. Winners claim automatically from the pool
6. The protocol fee is sent to the fee wallet on profitable claims

## Contract Design

The initial contract is centered around one main contract:

- `WagerDAO.sol` manages markets, bets, payouts, refunds, and platform accounting

The contract already defines the core protocol shape:

- `MarketStatus`: `OPEN`, `LOCKED`, `RESOLVED`, `CANCELLED`
- `Outcome`: `NONE`, `HOME`, `AWAY`, `DRAW`
- `Market`: match metadata, pool totals, creator, timestamps, status, result
- `Bet`: bettor, selected outcome, amount staked, timestamps, claim state

Current protocol constants:

- Minimum bet: `1 USDC`
- Community market creation fee: `10 USDC`
- Protocol fee: `2%` of profit

## Repo Structure

```text
wagerdao/
├── contracts/
│   └── WagerDAO.sol
├── .env.example
├── hardhat.config.js
├── package.json
└── README.md
```

As the build progresses, this repository will expand into contracts, tests, deployment scripts, automation, and a full frontend.

## Local Development

```bash
git clone https://github.com/Joel-eth/wagerdao.git
cd wagerdao
npm install
npm run compile
```

If you want to prepare for deployment later:

```bash
cp .env.example .env
```

Then fill in your RPC keys, private key, and related environment values.

## Tech Stack

- Solidity `0.8.20`
- Hardhat
- OpenZeppelin Contracts
- dotenv
- Base / Base Sepolia
- USDC

## What This Repo Will Become

The intended full system includes:

- smart contracts for market lifecycle and payouts
- a frontend for browsing matches and placing bets
- automation for market creation and result resolution
- testnet and mainnet deployment scripts
- verified contract source and transparent fee logic

## Follow The Build

If you want to watch WagerDAO take shape:

- Star the repo
- Watch the commit history
- Track contract development as features land
- Follow along as the protocol moves from skeleton to testnet to production

## Disclaimer

This project is under active development.
Nothing in this repository should be treated as production-ready yet.
Do not use unfinished contract code with real funds.

## License

MIT

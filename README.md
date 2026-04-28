# BidKernel

BidKernel is an open-source peer-to-peer marketplace protocol for trustless, decentralized exchange of goods and services.

## Overview

BidKernel lets any seller list a good or service on-chain and accept bids from buyers. When a seller accepts a bid, the buyer's funds are automatically locked in a dedicated **Escrow** smart contract. The escrow is released only when the buyer confirms delivery—or when a designated arbiter resolves a dispute. No central intermediary ever touches the funds.

```
Seller                Buyer                Arbiter
  |                     |                     |
  |-- createListing --> |                     |
  |                     |-- placeBid -------> |
  |<-- acceptBid -------|                     |
  |        ↓ Escrow deployed & funded        |
  |                     |-- confirmDelivery ->|
  |<-- funds released --|                     |
```

## Contracts

| Contract | Description |
|----------|-------------|
| `Marketplace.sol` | Core protocol: listing and bid lifecycle management |
| `Escrow.sol` | Minimal per-trade trustless escrow with dispute support |
| `interfaces/IMarketplace.sol` | Shared interface (events, enums, function signatures) |

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) ≥ 18
- npm

### Install dependencies

```bash
npm install
```

### Compile contracts

```bash
npm run compile
```

### Run tests

```bash
npm test
```

### Deploy locally

Start a local Hardhat node in one terminal:

```bash
npm run node
```

Deploy in a second terminal:

```bash
npm run deploy:local
```

## Protocol Flow

1. **Seller** calls `createListing(title, metadataURI, askPrice)`.
2. **Buyer** calls `placeBid(listingId)` with ETH attached (≥ `askPrice`).
3. **Seller** calls `acceptBid(listingId, bidId)` — an `Escrow` contract is deployed and funded with the bid amount.
4. After receiving the goods/service, the **Buyer** calls `confirmDelivery(listingId, bidId)` — the escrow releases funds to the seller.
5. If there is a dispute, the **Arbiter** calls `Escrow.resolveDispute(recipient)` to decide in favour of either party.

Rejected or withdrawn bids are automatically refunded to the bidder.

## License

MIT


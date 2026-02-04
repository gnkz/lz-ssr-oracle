# PSM Rate Provider

A LayerZero V2 cross-chain oracle system that synchronizes USDS savings rate data (SSR, chi, rho) from Ethereum Mainnet to Plasma.

## Overview

This project enables DApps on Plasma to access real-time savings rate data from the USDS protocol on Mainnet. The system uses LayerZero's OApp framework for secure cross-chain messaging.

```
Ethereum Mainnet                         Plasma Network
┌─────────────────┐                     ┌─────────────────┐
│  SSRForwarder   │ ── LayerZero V2 ──> │   SSROracle     │
│  (reads USDS)   │                     │ (stores rates)  │
└─────────────────┘                     └─────────────────┘
```

## Contracts

### SSRForwarder (Mainnet)

Reads interest rate data from the USDS protocol and forwards it cross-chain.

- `forward(dstEid, options)` - Send current SSR data to remote chain (operator-only)
- `quote(dstEid, options, payInLzToken)` - Estimate gas fees for messaging
- `setOperator(operator, isOperator)` - Manage operator permissions

### SSROracle (Plasma)

Receives and stores SSR data, provides conversion rate calculations.

- `getConversionRate()` - Calculate current conversion rate based on stored SSR data and elapsed time

## Setup

```bash
# Install dependencies
pnpm install

# Compile contracts
npx hardhat compile
```

## Testing

```bash
# Run all tests
npx hardhat test

# Run only Solidity tests
npx hardhat test solidity

# Run only TypeScript tests
npx hardhat test nodejs
```

## Deployment

### Configuration

Set environment variables for network RPC endpoints:

```bash
export MAINNET_RPC_URL=<mainnet-rpc>
export PLASMA_RPC_URL=<plasma-rpc>
export PRIVATE_KEY=<deployer-key>
```

### Deploy

The deployment script handles the full setup across both chains:

```bash
npx hardhat run scripts/deploy.ts
```

This will:
1. Deploy SSRForwarder on Mainnet with LayerZero configuration
2. Deploy SSROracle on Plasma with LayerZero configuration
3. Set cross-chain peers (link the contracts)
4. Forward initial SSR data to verify the setup

## Networks

| Network | Chain ID | LayerZero EID |
|---------|----------|---------------|
| Mainnet | 1        | 30101         |
| Plasma  | 30383    | 30383         |

## LayerZero Configuration

- **DVNs**: LZ Labs + Nethermind (2/2 required)
- **Confirmations**: 15 blocks
- **Receive Gas**: 100,000

## Tech Stack

- Hardhat 3 with Viem
- Solidity 0.8.28
- LayerZero OApp V2
- OpenZeppelin Contracts 5.x
- pnpm

## License

MIT

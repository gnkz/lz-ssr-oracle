# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Install dependencies
pnpm install

# Compile contracts
npx hardhat compile

# Run all tests (Solidity + TypeScript)
npx hardhat test

# Run only Solidity tests
npx hardhat test solidity

# Run only TypeScript/Node.js tests
npx hardhat test nodejs

# Deploy with Ignition (local simulation)
npx hardhat ignition deploy ignition/modules/Counter.ts

# Deploy to Plasma network
npx hardhat ignition deploy --network plasma ignition/modules/Counter.ts
```

## Architecture

This is a Hardhat 3 project implementing a LayerZero OApp for cross-chain messaging.

### Tech Stack
- **Hardhat 3** with `hardhat-toolbox-viem` for contract development
- **Solidity 0.8.28** with optimizer settings in production profile
- **LayerZero V2** (`@layerzerolabs/oapp-evm`) for cross-chain communication
- **OpenZeppelin Contracts** for standard utilities
- **Viem** for TypeScript/JS Ethereum interactions
- **pnpm** as package manager (version specified in mise.toml)

### Contract Structure
- `contracts/App.sol` - Main OApp contract (`MyOApp`) that extends LayerZero's OApp and OAppOptionsType3
  - Implements cross-chain string messaging via `sendString()` and `_lzReceive()`
  - Uses `quoteSendString()` for gas estimation before sending

### Network Configuration
- `hardhatMainnet` - EDR-simulated L1 chain
- `hardhatOp` - EDR-simulated OP chain
- `plasma` - HTTP network using `PLASMA_RPC_URL` and `PRIVATE_KEY` config variables

### Solidity Profiles
- `default` - Development build without optimizer
- `production` - Optimized build (200 runs)

# Bloc Step Arcade contracts

Solidity contracts for Bloc Step Arcade's token-funded play time, staking rewards, tips, and payouts on Base.

Related repositories:

- [Frontend](https://github.com/goldenoakmarketing/bloc-step-arcade-frontend): Next.js arcade and wallet interface.
- [Backend](https://github.com/goldenoakmarketing/bloc-step-arcade-backend): game sessions, notifications, and contract integration.

## Build and test

Install [Foundry](https://getfoundry.sh/getting-started/installation). CI uses Foundry **1.5.1**; the compiler and EVM target are set in `foundry.toml`.

```sh
git clone --recurse-submodules https://github.com/goldenoakmarketing/bloc-step-arcade.git
cd bloc-step-arcade
forge build
forge test -vv
```

For an existing clone, initialize the pinned dependencies first:

```sh
git submodule update --init --recursive
```

Tests use local mock tokens and price feeds. They do not require wallet credentials, a funded account, or access to a blockchain RPC. Foundry may download the pinned compiler on the first build. Keep the dependency revisions recorded by Git and `foundry.lock` together when updating libraries.

## Repository map

| Location | Purpose |
| --- | --- |
| `src/ArcadeVault.sol` | Play-time purchases, time balances, and vault distribution |
| `src/YeetEngine.sol` | Eligibility and yeet mechanics |
| `src/StakingPool.sol` | Token staking and reward accounting |
| `src/StabilityReserve.sol` | Reserve balances, price-feed integration, and buybacks |
| `src/TipBot.sol` | Authorized tipping and limits |
| `src/PoolPayout.sol` | Pool payouts |
| `src/interfaces/` | Contract interfaces |
| `test/` | Foundry tests and mocks |
| `script/` | Separate deployment scripts |
| `lib/` | Pinned Git submodules |

## Configuration and deployment

`.env.example` documents the configuration names. Copy it to a local `.env` only when configuring deployment; keep private keys and RPC credentials out of Git. `.env` variants, build output, and generated broadcast files are ignored.

Deployment is separate from the build and test commands. The scripts in `script/` use `vm.startBroadcast`; review the network, owner, game-server, and token addresses before running them. `DeployPoolPayout.s.sol` currently contains Base mainnet addresses. CI only builds and runs local tests and does not execute either deployment script.

The frontend and backend must use the addresses and interfaces for the deployed contracts. A successful source build does not change any deployed contract.

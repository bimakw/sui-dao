# Sui DAO

A complete Decentralized Autonomous Organization (DAO) implementation on Sui blockchain with governance tokens, proposal voting, and treasury management.

## Tech Stack

- **Language**: Move
- **Blockchain**: Sui Network
- **Patterns**: Governor, Treasury Multi-sig

## Modules

| Module | Description |
|--------|-------------|
| `governance_token` | Voting power token with delegation |
| `dao` | Proposal creation and voting |
| `treasury` | Multi-sig treasury management |

## Features

### Governance Token
- Voting power tracking
- Delegation support
- Power checkpointing

### DAO Governance
- Proposal creation with threshold
- Time-based voting periods
- Quorum requirements
- For/Against/Abstain voting
- Proposal lifecycle management

### Treasury
- Multi-sig spending proposals
- Approval threshold
- Signer management
- Proposal-based withdrawals

## Prerequisites

```bash
# Install Sui CLI
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch devnet sui
```

## Quick Start

```bash
# Clone repository
git clone https://github.com/bimakw/sui-dao.git
cd sui-dao

# Build
sui move build

# Test
sui move test

# Deploy
sui client publish --gas-budget 100000000
```

## Usage

### Setup DAO

```bash
# 1. Mint governance tokens
sui client call --package $PACKAGE --module governance_token --function mint \
  --args $TREASURY_CAP $GOV_CONFIG 1000000000000 $RECIPIENT \
  --gas-budget 10000000

# 2. Create DAO
sui client call --package $PACKAGE --module dao --function create_dao \
  --args "My DAO" 100000000 1000 604800000 86400000 259200000 \
  --gas-budget 10000000

# Args: name, proposal_threshold, quorum_bps (10%), voting_period (7 days),
#       execution_delay (1 day), execution_window (3 days)
```

### Governance Flow

```bash
# 1. Create proposal
sui client call --package $PACKAGE --module dao --function create_proposal \
  --args $DAO $GOV_CONFIG "Proposal Title" "Description..." 0x6 \
  --gas-budget 10000000

# 2. Cast vote (1 = for, 0 = against, 2 = abstain)
sui client call --package $PACKAGE --module dao --function cast_vote \
  --args $PROPOSAL $GOV_CONFIG 1 0x6 \
  --gas-budget 10000000

# 3. Finalize after voting ends
sui client call --package $PACKAGE --module dao --function finalize_proposal \
  --args $DAO $PROPOSAL 0x6 \
  --gas-budget 10000000

# 4. Execute passed proposal
sui client call --package $PACKAGE --module dao --function execute_proposal \
  --args $DAO $PROPOSAL 0x6 \
  --gas-budget 10000000
```

### Delegation

```bash
# Delegate voting power
sui client call --package $PACKAGE --module governance_token --function delegate \
  --args $GOV_CONFIG $TOKEN $DELEGATE_ADDRESS \
  --gas-budget 10000000

# Remove delegation
sui client call --package $PACKAGE --module governance_token --function undelegate \
  --args $GOV_CONFIG $TOKEN \
  --gas-budget 10000000
```

### Treasury Management

```bash
# Create treasury with 3 signers, 2 required approvals
sui client call --package $PACKAGE --module treasury --function create_treasury \
  --args '["0xSigner1", "0xSigner2", "0xSigner3"]' 2 \
  --gas-budget 10000000

# Deposit to treasury
sui client call --package $PACKAGE --module treasury --function deposit \
  --args $TREASURY $COIN \
  --gas-budget 10000000

# Create spending proposal
sui client call --package $PACKAGE --module treasury --function create_spending_proposal \
  --args $TREASURY $SIGNER_CAP $RECIPIENT 1000000000 "Payment for services" \
  --gas-budget 10000000

# Approve proposal (other signers)
sui client call --package $PACKAGE --module treasury --function approve_proposal \
  --args $TREASURY $PROPOSAL $SIGNER_CAP \
  --gas-budget 10000000

# Execute after approvals
sui client call --package $PACKAGE --module treasury --function execute_spending \
  --args $TREASURY $PROPOSAL \
  --gas-budget 10000000
```

## Architecture

```
sui-dao/
├── sources/
│   ├── governance_token.move  # Voting power token
│   ├── dao.move               # Proposal & voting
│   └── treasury.move          # Multi-sig treasury
├── tests/
├── Move.toml
└── README.md
```

## DAO Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `proposal_threshold` | Min tokens to create proposal | 100 GOV |
| `quorum_bps` | Min participation (basis points) | 1000 (10%) |
| `voting_period_ms` | Voting duration | 604800000 (7 days) |
| `execution_delay_ms` | Delay after vote passes | 86400000 (1 day) |
| `execution_window_ms` | Time to execute | 259200000 (3 days) |

## Proposal States

| State | Description |
|-------|-------------|
| `Pending` | Created, waiting to start |
| `Active` | Voting in progress |
| `Defeated` | Failed (quorum or votes) |
| `Succeeded` | Passed, awaiting execution |
| `Executed` | Successfully executed |
| `Expired` | Execution window passed |

## Security Features

- Proposal threshold prevents spam
- Quorum ensures participation
- Time-locked execution for review
- Delegation without token transfer
- Multi-sig treasury protection
- Vote receipts for transparency

## Testing

```bash
# Run all tests
sui move test

# Run specific module tests
sui move test dao_tests

# With verbose output
sui move test -v
```

## License

MIT License with Attribution - See [LICENSE](LICENSE)

Copyright (c) 2024 Bima Kharisma Wicaksana

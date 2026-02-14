# Sui DAO

On-chain DAO with governance tokens (delegation support), proposal voting (for/against/abstain with quorum), and a multi-sig treasury.

## Building & Testing

```bash
sui move build
sui move test
```

## Modules

- **governance_token** — voting power, delegation, checkpointing
- **dao** — proposals with threshold, time-locked voting, execution delay
- **treasury** — multi-sig spending proposals with configurable approval threshold

## License

MIT with attribution — see [LICENSE](LICENSE).

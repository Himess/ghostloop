# GhostLoop

Private leverage and borrowing on Vesu.

GhostLoop is building a focused Starknet Mainnet experience for borrowing USDC
and opening leveraged ETH positions on Vesu without linking those positions to
the user's public wallet.

STRK20 provides private balances and unlinkable execution identities. Vesu
provides lending and risk management. Ekubo provides swap liquidity for
Multiply and unwind flows.

> Status: architecture validation in progress. No deployment, demo URL,
> contract address, or transaction hash is claimed yet.

## Product flows

- **Borrow:** private ETH → position Shadow Account → Vesu ETH/USDC position →
  borrowed USDC returned to a private STRK20 balance.
- **Multiply:** private ETH → position Shadow Account → Vesu Multiply + Ekubo →
  persistent leveraged ETH position.
- **Unwind:** Vesu Multiply closes debt and collateral → residual ETH returned
  to a private STRK20 balance.

## Privacy model

GhostLoop aims to hide the link between a user's public wallet and the Vesu
position. The Shadow Account address, collateral, debt, health, swaps, timing,
and other onchain activity remain public. See
[docs/PRODUCT.md](docs/PRODUCT.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Current milestone

The first milestone is evidence, not UI polish:

1. ~~Feature-detect current Mainnet Shadow Account wallet execution.~~ Native
   dapp Wallet API support is not currently shipped; see the decision request.
2. ~~Verify live STRK20 and Vesu ETH/USDC contracts and configuration.~~
3. ~~Verify whether a canonical Vesu Multiply deployment exists.~~
4. Prove borrow, Multiply, and full unwind on a Mainnet fork.
5. Resolve Architecture A versus the documented fallback before implementing
   position ownership.

Research is recorded in [docs/RESEARCH_LOG.md](docs/RESEARCH_LOG.md), and
architectural decisions in [docs/DECISIONS.md](docs/DECISIONS.md).

## Verification tools

Node.js 22 or newer is required.

```bash
npm install
npm run check
npm run verify:addresses
npm run verify:tx -- <STARKNET_MAINNET_TX_HASH>
npm run evidence
```

`STARKNET_RPC_URL` may point to an authenticated Alchemy Mainnet endpoint. The
read-only public sprint RPC is used when it is unset. Never commit API keys.

The transaction verifier requires both successful execution and receipt/trace
evidence that the canonical STRK20 pool was touched. It does not treat an
address appearing only in calldata as proof.

## License

[MIT](LICENSE)

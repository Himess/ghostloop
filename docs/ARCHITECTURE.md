# Architecture

## Status

The architecture is not locked. Architecture A is preferred but must pass a
real current-wallet capability test on Starknet Mainnet.

## Preferred Architecture A

```text
GhostLoop web app
  → STRK20 Privacy Wallet API
  → STRK20 Privacy Pool
  → official Shadow Account Anonymizer
  → one Shadow Account per position
  → Vesu V2 Pool + Vesu Multiply + Ekubo
```

Each position uses the `GHOSTLOOP` dapp name and a separate nonce. The Vesu
position owner and caller should both be that position's Shadow Account.

Expected borrow lifecycle:

```text
private ETH
  → withdraw to predicted Shadow Account
  → approve Vesu + modify position
  → borrowed USDC at Shadow Account
  → collect only the gained USDC into an STRK20 note
```

Expected leverage lifecycle:

```text
private ETH
  → withdraw to predicted Shadow Account
  → approve Multiply + delegate from Vesu position
  → Multiply increase lever with Ekubo settlement
  → persistent Vesu position owned by Shadow Account
```

Expected unwind lifecycle:

```text
Shadow Account
  → Multiply decrease lever with close_position
  → debt and collateral become zero
  → residual ETH at Shadow Account
  → collect ETH into an STRK20 note
```

## Architecture gate

Architecture A is viable only if the current privacy-enabled Mainnet wallet can
actually execute the Shadow Account action. Specification presence and version
strings are insufficient; the implementation must be feature-detected and
exercised.

## Fallback Architecture B

A custom GhostLoop anonymizer and per-position contract will be considered only
if Architecture A is proven unavailable or unusable. That fallback introduces
new authentication, replay-protection, custody, audit, and deployment risks and
requires an explicit design decision before implementation.

## Unverified items

- Current STRK20 Mainnet pool and Shadow Account Anonymizer addresses.
- Wallet action support and exact action schemas.
- Current Vesu ETH/USDC market and risk parameters.
- Canonical Vesu Multiply Mainnet deployment and class hash.
- Exact ABI/calldata, token approvals, collect policy, and action ordering.

These items are tracked in [RESEARCH_LOG.md](RESEARCH_LOG.md).

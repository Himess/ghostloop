# Architecture

## Status

Option B is approved as a temporary, replaceable compatibility layer. Native
STRK20 Shadow Accounts remain the preferred long-term execution identity.

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

## Current Architecture B

```text
GhostLoop product flows
  → PositionExecutor
  → GhostPositionExecutor
  → STRK20 Wallet API ordinary privacy_invoke
  → GhostLoopAnonymizer
  → one GhostPosition per position
  → Vesu Prime / canonical Vesu Multiply V2 / Ekubo
```

The execution boundary exposes only the lifecycle operations represented by:

```text
CreateAndFund  Borrow  Repay  CloseBorrow  IncreaseLeverage  Unwind
```

It does not expose an arbitrary Starknet call primitive.

### Wallet action serialization

The ordinary Wallet API adapter builds one typed `STRK20_ACTION[]` sequence per
closed operation. Private input is consumed by the helper's single invoke;
Borrow and unwind add one `OPEN` transfer, while CloseBorrow adds a collateral
note and an optional debt-refund note. Calldata uses the wallet-resolved
`${openNoteIds[N]}` placeholder and never requests a viewing key.

`scripts/verify-wallet-actions.ts` checks fixed golden sequences and independently
asks starknet.js to populate `privacy_invoke` from the generated anonymizer ABI.
The two felt arrays must match for all six enum variants. The ABI verifier also
locks enum order because Cairo serializes the variant index into calldata.

All private helper inputs are limited to `u128`; the helper ABI encodes them as
`u256` with a zero high limb. This preserves the pool-facing low-felt amount
convention while rejecting ambiguous oversized input client-side.

### Wallet capability and simulation boundary

Browser discovery is loaded only when the user opens the wallet picker. Each
wallet is queried with `supportedWalletApi` and `requestChainId` before account
access; GhostLoop requires Wallet API `0.10.3+` and `SN_MAIN`. Capability
detection never calls `strk20Balances`, so it does not ask for unnecessary
private-data consent.

After an explicit compatible-wallet connection, GhostLoop narrows the runtime
account object to a single `prepare(actions)` function. That function always
calls `strk20PrepareInvoke(actions, true)` and does not expose transaction
submission. The browser provider uses a public Mainnet RPC; authenticated RPC
configuration and environment variables stay server-side.

### Identity and authorization

Each GhostPosition owns its Vesu collateral and debt and receives one fresh
STARK-curve capability public key. The matching private key stays client-side.
Every lifecycle action reconstructs a Poseidon authorization hash over:

```text
GhostLoop domain + version
SN_MAIN chain id
GhostPosition address
explicit action id
complete parameters hash
exact next nonce
deadline
```

The position rejects the wrong caller, replayed/skipped nonce, expired
authorization, wrong chain/position signature, changed parameters, invalid
signature, and unsupported actions.

### Deployment and funding

The STRK20 pool calls the pinned GhostLoopAnonymizer. The anonymizer derives or
deploys the requested GhostPosition from the position public key/salt, transfers
the exact private input to it, and invokes one explicit lifecycle operation.
Deployment must occur inside this path so Semih's public wallet never becomes
the deployer or Vesu position owner.

### Settlement

For outputs, the anonymizer snapshots its token balance, invokes the position,
measures the actual positive delta, approves the calling STRK20 pool, and
returns `Span<OpenNoteDeposit>`. At most one output note per token is allowed.
Multiply open may return an empty span; Borrow and unwind settle USDC or ETH to
open notes.

### Product dashboard and live data boundary

The Next.js App Router page reads the Vesu Prime ETH/USDC snapshot on the
server. Only a minimal serializable market view crosses into the interactive
dashboard; RPC configuration and environment variables remain server-side.
The client computes Borrow and Multiply previews from the current ETH oracle,
max LTV, and a 10-percentage-point product buffer.

The dashboard is deliberately fail-closed. Market viability, valid oracles,
input safety, independent review, wallet compatibility, and capability-key
backup must all pass before transaction preparation can be enabled. It shows
which linkage is private and which position facts remain public, and it does
not fabricate a wallet connection, position, quote, or transaction request.

## Native migration seam

When a connected wallet advertises and successfully executes the Shadow Account
Wallet API, add `NativeShadowAccountExecutor` and switch adapters. Product
models, forms, risk calculations, lifecycle commands, and position display must
not depend on GhostPosition deployment or capability-key details.

## Proof-gate status

- ~~Deterministic GhostPosition deployment from the anonymizer path.~~
- ~~Every adversarial authorization and replay case.~~
- ~~Exact Vesu Borrow open/repay/close behavior on a Mainnet fork.~~
- ~~Exact canonical Multiply increase/full-unwind calldata on a Mainnet fork.~~
- ~~STRK20 input accounting and open-note output settlement.~~
- ~~Exact Wallet API action and helper calldata serialization.~~
- ~~Encrypted per-position capability keys and authenticated backup/import.~~
- ~~Live Vesu-backed Borrow/Multiply previews with a fail-closed execution
  gate.~~
- ~~Wallet discovery, `0.10.3+`/Mainnet capability gates, and a prepare-only
  simulation boundary.~~
- ~~Capability-key passphrase, encrypted download, and irreversible-loss
  acknowledgement in the UI.~~
- Connected-wallet `strk20PrepareInvoke(actions, true)` simulation against a
  deployed reviewed helper.

These items are tracked in [RESEARCH_LOG.md](RESEARCH_LOG.md).

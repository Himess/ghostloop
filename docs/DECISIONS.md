# Decisions

## D-001 — Build the architecture proof before UI polish

- **Status:** Accepted
- **Date:** 2026-08-31
- **Decision:** Validate current Shadow Account execution, Vesu borrowing,
  Multiply, and full unwind before investing in production UI work.
- **Reason:** Wallet rollout and Mainnet Multiply deployment are hard gates. A
  polished interface cannot compensate for an unproven execution lifecycle.

## D-002 — Option B as a replaceable execution compatibility layer

- **Status:** Accepted
- **Date:** 2026-08-31
- **Decision:** Proceed with ordinary STRK20 Wallet API `privacy_invoke`, a
  narrowly scoped `GhostLoopAnonymizer`, and one signed `GhostPosition` contract
  per position. Keep this behind a `PositionExecutor` boundary so native Shadow
  Accounts can replace it without changing product logic.
- **Reason:** Current Ready `5.33.9` exposes ordinary STRK20 methods but not the
  native Shadow Account action. Waiting would put the Mainnet submission behind
  an external wallet rollout with no committed delivery date.
- **Constraints:** The public wallet must never own the Vesu position. Each
  position receives a fresh client-side capability key. Authorization binds
  domain/version, chain id, position address, explicit action, full parameter
  hash, monotonic nonce, and deadline. The contracts expose no arbitrary-call
  path and allow only ETH, USDC, Vesu Prime, canonical Multiply V2, and the
  Ekubo contracts reached by Multiply.
- **Migration:** `GhostPositionExecutor` is the current adapter;
  `NativeShadowAccountExecutor` is the future adapter. GhostPosition-specific
  calldata, key storage, deployment, and settlement must remain inside the
  current adapter.
- **Terminology:** The limitation is a current Wallet API capability/rollout
  gap, not an Argent or Ready bug.
- **Approval:** Semih approved Option B after reviewing
  [DESIGN_DECISION_REQUEST.md](DESIGN_DECISION_REQUEST.md).

## D-003 — No value-bearing deployment before security and fork gates

- **Status:** Accepted
- **Date:** 2026-08-31
- **Decision:** Do not deploy experimental GhostLoop contracts with value until
  authorization, replay, allowlist, accounting, Vesu Borrow close, Multiply,
  and unwind tests pass.
- **Reason:** Option B adds a new custody-adjacent capability-key and contract
  authorization surface. The sprint deadline does not justify risking funds.

# GhostLoop contracts

> Security status: experimental, unaudited, and not approved for deployment.

This package implements the temporary Option B compatibility layer. It is
deliberately not a generic smart account. `GhostPosition` has one capability
key and explicit GhostLoop lifecycle entry points; no arbitrary call entry point
exists.

Current checkpoint:

- domain-separated per-position authorization hash;
- chain, position, action, complete parameters, nonce, and deadline binding;
- exact-next-nonce replay protection;
- pool-pinned `GhostLoopAnonymizer` deployment and funding path;
- deterministic position addresses derived from capability key, salt, class,
  constructor calldata, and anonymizer address;
- capability-signed creation binding chain, predicted position, amount, nonce,
  and deadline;
- explicit Vesu Prime Borrow, Repay, and CloseBorrow entry points;
- closed `CreateAndFund | Borrow | Repay | CloseBorrow` anonymizer operation
  enum, with no arbitrary-call variant;
- exact input forwarding verified by helper balance changes;
- Borrow credits one measured, non-zero USDC output and approves only the
  pinned pool;
- Repay forwards exact USDC and returns an empty deposit span;
- CloseBorrow credits measured ETH and an optional measured USDC refund to
  distinct open notes;
- explicit rejection of zero output, negative delta, `u128` note overflow,
  position-reported/output-delta mismatch, missing notes, and unused refund
  notes;
- 24 passing isolated Linux contract tests plus one ignored-by-default,
  pinned-block Mainnet fork lifecycle test against canonical Vesu Prime;
- no Multiply dispatch yet.

Do not deploy until all gates in [`../docs/SECURITY.md`](../docs/SECURITY.md)
pass.

## Toolchain

- Scarb `2.18.0`
- Cairo `2.18.0`
- Starknet Foundry / `snforge_std` `0.63.0`

```bash
scarb build
snforge test
snforge test test_vesu_mainnet_fork --ignored
```

The fork test uses archive block `4172487`, immediately before the canonical
Prime ETH/USDC market's debt cap was reduced. It opens a real 0.02 ETH / 20
USDC position, partially repays it, closes it, verifies both assets are
returned, and verifies the capability nonce sequence. The public archive RPC
is read-only; all mutations live only inside Starknet Foundry's fork.

On native Windows, Scarb builds locally; contract-state tests run in Linux CI
because Starknet Foundry officially supports Windows through WSL.

## Upstream ABI provenance

The minimal Vesu `Position`, `Amount`, `ModifyPositionParams`, and pool method
shapes in `src/interfaces.cairo` are adapted from
[`vesuxyz/vesu-v2`](https://github.com/vesuxyz/vesu-v2/tree/2165e6c01bc4c6386d7cc57ece6d13b3d8a3560f),
which is MIT licensed. No Vesu execution implementation is vendored here; the
types keep GhostLoop calls typed instead of hand-encoding raw calldata. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

The `OpenNoteDeposit` ABI shape is reproduced from StarkWare's Apache-2.0
`starknet-privacy` package so the privacy pool can deserialize the helper's
return value exactly.

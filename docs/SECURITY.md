# Security

GhostLoop Option B is an experimental compatibility layer. It is not audited
and must not hold meaningful value until every gate below passes.

## Trust boundary

| Component | Holds or observes |
| --- | --- |
| Ready wallet | STRK20 viewing key, notes, proof construction and submission |
| GhostLoop browser | One capability private key per position; public position data |
| GhostLoop backend | No viewing key, capability key, or signing authority |
| STRK20 pool | Private protocol state; public deposits, withdrawals and timing |
| GhostLoopAnonymizer | Public input/output amounts during one atomic invoke |
| GhostPosition | Capability public key, nonce and public Vesu position |
| Vesu/Ekubo | Public collateral, debt, swaps, health and timing |

## Authorization invariant

The capability private key never enters calldata, source control, analytics,
telemetry, console output, or backend logs. A signed authorization is valid only
for one action on one position and one chain before one deadline at the exact
next nonce.

Required negative tests:

- caller is not the pinned anonymizer;
- nonce is reused or skipped;
- deadline is expired;
- signature was produced for another chain;
- signature was produced for another position;
- action or any parameter changed after signing;
- signature is malformed or belongs to another key;
- target/action is outside the explicit allowlist;
- output delta is zero, negative, or exceeds `u128`;
- duplicate output notes target the same token.

## Key storage

The MVP will use a fresh key per position, encrypted client-side with WebCrypto
before persistence in IndexedDB. There is no backend recovery. Export/backup
must be explicit and encrypted, and the UI must warn that losing a position key
can make repayment or unwind impossible.

## Deployment gates

No value-bearing Mainnet deployment until:

1. authorization and replay tests pass;
2. allowlist and settlement accounting tests pass;
3. Borrow open/repay/close passes on a Mainnet fork;
4. Multiply increase/full unwind passes on a Mainnet fork;
5. an independent contract review is completed; and
6. the first deployment uses the smallest practical values.

## Anonymizer deployment boundary

- `GhostLoopAnonymizer` accepts `privacy_invoke` only from its immutable STRK20
  pool address.
- Position deployment uses the anonymizer contract as deployer, so no public
  wallet appears in the deployment path.
- Creation authorization binds the actual chain ID, predicted position address,
  create-and-fund action, full amount/key/salt parameters, nonce zero, and a
  deadline.
- `privacy_invoke` dispatches only `CreateAndFund`, `Borrow`, `Repay`,
  and `CloseBorrow`; there is no raw target, selector, or calldata field.
- Input forwarding is accepted only when the helper's measured token balance
  decreases by the exact declared amount.
- Funding and Repay return an exact empty `Span<OpenNoteDeposit>`.
- Borrow and CloseBorrow ignore untrusted protocol return values for
  settlement, use positive helper balance deltas, require them to fit `u128`,
  approve only the pinned pool, and then return exact deposit instructions.
- CloseBorrow requires one ETH note and requires a second USDC note if and only
  if a non-zero debt refund was actually received.
- The helper has no arbitrary-call entry point. Any ABI expansion fails CI.

The local stateful settlement suite covers these invariants, but it is not a
substitute for the required Vesu Mainnet-fork lifecycle test or an independent
audit.

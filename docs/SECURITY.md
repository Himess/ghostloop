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

The MVP uses a fresh Stark-curve key per position. `WebCryptoPositionKeyStore`
encrypts the 32-byte private key with AES-256-GCM before persistence through
`IndexedDbPositionKeyPersistence`. The AES key is non-extractable and derived
only in memory from a user passphrase with PBKDF2-SHA-256, a random per-record
128-bit salt, and 600,000 iterations. Each record uses a fresh 96-bit IV and
authenticates its schema version, random reference, and capability public key.
Decrypted byte arrays are cleared after signing; neither the passphrase nor raw
private key is persisted.

The PBKDF2 work factor matches the current
[OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
recommendation for PBKDF2-HMAC-SHA-256. The 256-bit AES-GCM derivation and
12-byte random IV use the browser primitives specified by
[Web Cryptography Level 2](https://www.w3.org/TR/WebCryptoAPI/). Argon2id is
memory-hard and preferable where a reviewed browser implementation is already
available; GhostLoop currently avoids adding a separate key-derivation runtime
to this narrow MVP.

Encrypted export is the stored authenticated envelope itself. Import verifies
the envelope, decrypts it, and proves the recovered private key matches the
declared Stark public key before accepting the record. Wrong passwords,
tampering, duplicate references, oversized/unknown envelopes, signing while
locked, and missing records are rejected. There is no backend recovery.

The UI must require an explicit encrypted backup and warn that losing either
the backup/passphrase or browser storage can make repayment and unwind
impossible. JavaScript cannot guarantee immediate erasure of immutable strings
or engine-internal cryptographic state, so this is an experimental browser
custody boundary rather than hardware-wallet-grade storage.

## Deployment gates

No value-bearing Mainnet deployment until:

1. authorization and replay tests pass;
2. allowlist and settlement accounting tests pass;
3. Borrow open/repay/close passes on a Mainnet fork and the current live market
   preflight reports enough cap above Vesu's minimum-debt floor;
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
  `CloseBorrow`, `IncreaseLeverage`, and `Unwind`; there is no raw target,
  selector, route, or calldata field.
- Input forwarding is accepted only when the helper's measured token balance
  decreases by the exact declared amount.
- Funding and Repay return an exact empty `Span<OpenNoteDeposit>`.
- Borrow and CloseBorrow ignore untrusted protocol return values for
  settlement, use positive helper balance deltas, require them to fit `u128`,
  approve only the pinned pool, and then return exact deposit instructions.
- CloseBorrow requires one ETH note and requires a second USDC note if and only
  if a non-zero debt refund was actually received.
- IncreaseLeverage pins Vesu Prime, canonical Multiply V2, and the one-hop
  Ekubo ETH/USDC pool key in contract code. It delegates only the pinned
  Multiply contract and binds margin, debt, and minimum swap output in the
  capability signature.
- Unwind binds the maximum ETH swap input and minimum returned collateral,
  requires the Vesu position to end at exact zero, measures returned ETH, and
  creates one ETH note. Its non-zero ETH input is a settlement anchor required
  by the ordinary `privacy_invoke` path and is included in the measured output.
- The helper has no arbitrary-call entry point. Any ABI expansion fails CI.

The local stateful settlement suite covers these invariants. The canonical
Vesu lifecycle also passes at pinned Mainnet block `4172487`, but the current
Prime ETH/USDC cap is only 1 USDC while the debt floor is roughly 10 USDC.
`npm run preflight:vesu` therefore blocks a live deployment. The historical
fork proof is not evidence that today's market accepts a new position, and
neither suite substitutes for an independent audit. The canonical Multiply V2
increase/full-unwind lifecycle also passes at that pinned block.

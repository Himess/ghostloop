# Research Log

Research entries pin exact source versions and distinguish verified evidence
from assumptions. Times are recorded in UTC.

## 2026-08-31 — STRK20 Private Sprint rules and repository schema

- **Time:** 2026-08-31T18:35Z
- **Source:** `starkience/strk20-hackathon`, `README.md`
- **Commit:** `4df40a2f58146d5d6738502b335809db04a5fa72`
- **Finding:** Registration is a pull request adding `repo_url` and one or more
  Telegram usernames to `registry.json`. Project name and one-liner are derived
  from GitHub; category defaults to `Other` unless explicitly set. A root
  `strk20.json` accepts `transactions` and `contracts` arrays, with demo fields
  added when they exist. Scoring requires three successful Mainnet transactions
  touching the STRK20 pool. The published deadline is September 7, 2026 at
  23:59 UTC; winners are announced September 11.
- **Confidence:** High — current official repository source.
- **Impact:** The project starts with empty transaction and contract arrays.
  Registration preparation can proceed, but the Telegram username must come
  from the user or another trusted source.

## 2026-08-31 — Required upstream source heads

- **Time:** 2026-08-31T18:42Z
- **Source:** GitHub repository and commit APIs
- **Finding:** The current default-branch heads selected for the first research
  pass are:
  - `starkware-libs/starknet-privacy` —
    `4db755b9512f00b540126737b605472ea2275e15`
  - `starkware-libs/starknet-specs` —
    `1e79af61071a77e0031d397e1fbe81e9a0637072`
  - `starkience/strk20-hackathon` —
    `4df40a2f58146d5d6738502b335809db04a5fa72`
  - `starkience/strk20-agent-skills` —
    `8dfd751eb827c5303446b26df63b3aa472aa4d91`
  - `vesuxyz/vesu-v2` —
    `2165e6c01bc4c6386d7cc57ece6d13b3d8a3560f`
  - `vesuxyz/vesu-v2-periphery` —
    `3aa1b95af0663cd1fc575cef31ded88816e67277`
  - `EkuboProtocol/starknet-contracts` —
    `6d58acbcc6c0e38b77e5d1fa45fd17817c789523`
- **Confidence:** High — current GitHub default-branch commit objects.
- **Impact:** Findings from moving upstream branches will cite these immutable
  commits. Production dependencies will not be pinned until compatibility is
  verified.

## 2026-08-31 — Shadow Account API exists in current specifications and clients

- **Time:** 2026-08-31T18:43Z
- **Source:** `starkware-libs/starknet-specs/wallet-api/wallet_rpc.json` and
  `starkware-libs/starknet-privacy/client/src/*` at the commits above; GitHub
  code search was used only to locate the primary-source files.
- **Finding:** The current Wallet API specification contains
  `wallet_strk20ShadowAccountCommitment` and a `shadow_account_invoke` action.
  The current `starknet-privacy` client also contains builder and interface
  support for `shadow_account_invoke`.
- **Confidence:** High for specification/client availability; **not yet
  evidence of wallet support**.
- **Impact:** Architecture A remains plausible, but it is not accepted until a
  current privacy-enabled Mainnet wallet advertises and successfully executes
  the action.

## 2026-08-31 — Current builder guidance rejects Wallet API sub-accounts

- **Time:** 2026-08-31T19:22Z
- **Source:** `https://strk20-by-example.org/llms-full.txt`; STRK20 starter kit
  at `Akashneelesh/strk20-starter-kit` commit
  `187fe789dd4f5de14ccb0953abfdb49a26643664`; sprint `IDEAS.md` at
  `4df40a2f58146d5d6738502b335809db04a5fa72`.
- **Finding:** The current full builder guide says the SDK sub-account route is
  available but the dapp Wallet API route is still pending. The current starter
  kit pins `@starknet-io/types-js` `0.10.3` and exposes ordinary STRK20
  shield/unshield/transfer/`privacy_invoke` flows, not sub-account execution.
  The sprint ideas page independently labels sub-accounts as not shipped yet.
- **Confidence:** High — three current builder-facing sources agree.
- **Impact:** A normal GhostLoop dapp cannot ship Architecture A through the
  currently documented Wallet API. Using the SDK directly would make GhostLoop
  responsible for privacy/account keys and changes the intended custody model.

## 2026-08-31 — Ready 5.33.9 lacks native Shadow Account dispatch

- **Time:** 2026-08-31T19:05Z
- **Source:** Installed Ready X Chrome extension `5.33.9`, extension id
  `dlcobpjiigpikoobohmabehhmhfoodbb`; static inspection of its installed
  `inpage.js` request dispatcher.
- **Finding:** The bundle dispatches `wallet_strk20InvokeTransaction`,
  `wallet_strk20PrepareInvoke`, `wallet_strk20Balances`,
  `wallet_supportedSpecs`, and `wallet_supportedWalletApi`. It contains neither
  `wallet_strk20ShadowAccountCommitment` nor `shadow_account_invoke`; unmapped
  requests reach `Unknown request type`. The bundle identifies Wallet API
  `0.10.3`. A GUI runtime probe was attempted but the automation layer stopped
  because it could not establish the current Windows browser URL with enough
  confidence; no wallet approval or transaction was attempted.
- **Confidence:** High for missing dispatcher/schema support; runtime invocation
  remains unexecuted.
- **Impact:** Architecture A is rejected for the installed wallet version. A
  design decision is required before implementing the fallback.

## 2026-08-31 — Vesu V2 Mainnet path and ownership constraints verified

- **Time:** 2026-08-31T18:58Z
- **Source:** `vesuxyz/vesu-v2` commit
  `2165e6c01bc4c6386d7cc57ece6d13b3d8a3560f`;
  `vesuxyz/vesu-v2-periphery` commit
  `3aa1b95af0663cd1fc575cef31ded88816e67277`; Vesu changelog commit
  `caa47ec390cf2d8e9567e225f736eb9dfc39ac61`; Starknet Mainnet RPC at block
  `14162066`.
- **Finding:** The canonical Prime pool is
  `0x451fe483d5921a2919ddd81d0de6696669bccdacd859f72a4fba7656b97c3b5` and
  canonical Multiply V2 is
  `0x7964760e90baa28841ec94714151e03fbc13321797e68a874e88f27c9d58513`.
  Prime ETH/USDC reports max LTV `0.8e18` and liquidation factor `0.9e18`.
  `modify_position` requires user ownership/delegation for debt increase or
  collateral decrease. Multiply requires `user == get_caller_address()` and
  uses Ekubo lock/callback settlement rather than a Vesu flash loan.
- **Confidence:** High — source and live chain state agree.
- **Impact:** A pseudonymous contract/account can own the real position, but it
  must originate Multiply calls and delegate Multiply in Vesu before leverage.

## 2026-08-31 — Sprint registration submitted

- **Time:** 2026-08-31T19:16Z
- **Source:** `starkience/strk20-hackathon` pull request `#254`, commit
  `9a230d84fba7c83598cdf3057279b2bc289c26ab`.
- **Finding:** The PR added one two-field object for
  `https://github.com/Himess/ghostloop` and Telegram `SemihCivelek`. Only
  `registry.json` changed. The registration workflow applied it to upstream
  `main` as `66b6ba5`, then intentionally closed rather than merged the PR to
  avoid concurrent-registration conflicts. A fresh upstream `registry.json`
  read confirmed the exact entry.
- **Confidence:** High — GitHub PR diff verified.
- **Impact:** The only deadline-bound application step is complete; GhostLoop is
  registered and should appear on the hub after its refresh cycle.

## 2026-08-31 — Mainnet evidence tooling verified

- **Time:** 2026-08-31T19:31Z
- **Source:** GhostLoop `scripts/verify-addresses.ts` and
  `scripts/verify-mainnet-tx.ts`; Lava Starknet Mainnet RPC.
- **Finding:** At block `14163451`, all pinned class hashes, chain id, Vesu Prime
  name, ETH/USDC risk values, and Multiply's Ekubo Core storage matched. The
  transaction verifier was exercised against a recent unrelated STRK20 pool
  transaction
  `0x5a22066c25cd6b337a9a16bef431546a6eca86a6e4ebd6484cd65a8317a4877`
  at block `14160026`; it reported `SUCCEEDED` and found direct pool evidence in
  both receipt events and the execution trace.
- **Confidence:** High — deterministic scripts and live RPC responses.
- **Impact:** Future GhostLoop transaction hashes can be rejected automatically
  if they fail or do not actually execute against the canonical pool. The test
  transaction belongs to another activity and is deliberately not placed in
  GhostLoop's `strk20.json`.

## 2026-09-01 — Ordinary Wallet API helper settlement passes locally

- **Time:** 2026-09-01T00:26+03:00
- **Source:** GhostLoop Cairo contracts on Scarb/Cairo `2.18.0` and Starknet
  Foundry `0.63.0`, executed on the isolated Survivors Linux toolchain.
- **Finding:** `GhostLoopAnonymizer` now has a closed
  `CreateAndFund | Borrow | Repay | CloseBorrow` dispatch. Stateful token and
  position mocks verified exact input forwarding, balance-delta settlement,
  pool-only approvals, optional close refund notes, zero output rejection,
  `u128` overflow rejection, and reported-versus-measured output mismatch.
  All 24 contract tests passed and the production ABI remained limited to 7
  position and 5 anonymizer entry points.
- **Confidence:** High for local contract invariants; no claim about live Vesu
  behavior or Wallet API calldata compatibility yet.
- **Impact:** Local STRK20 settlement accounting is implemented. The next hard
  gates are a real Wallet API `strk20PrepareInvoke(..., true)` dry-run and the
  Vesu Borrow/Repay/Close Mainnet-fork lifecycle.

## 2026-09-01 — Canonical Vesu lifecycle passes; live ETH/USDC market is gated

- **Time:** 2026-09-01T02:10+03:00
- **Source:** Canonical Vesu Prime Mainnet contract, Vesu V2 source commit
  `2165e6c01bc4c6386d7cc57ece6d13b3d8a3560f`, and GhostLoop's Starknet
  Foundry `0.63.0` fork test.
- **Finding:** Governance transaction
  `0x7881366874d2627df382748a100346f6514856d0ea47fd0c4a22e6c0aad9a9f`
  changed Prime's ETH/USDC debt cap in block `4172488`; the chain-reported cap
  changed from `50000000000000000000000000` to `1000000`. At the immediately
  preceding block `4172487`, GhostLoop opened a real 0.02 ETH / 20 USDC Vesu
  position, partially repaid 5 USDC, fully closed the remaining debt, recovered
  collateral and excess USDC, and consumed nonces 0–2. The test passed against
  canonical Mainnet Vesu, ETH, and USDC contracts without broadcasting a
  transaction. At live block `14175787`, the market has zero total nominal
  debt, a 1 USDC cap, a 10e18 value floor, and a valid approximately 1e18 USDC
  oracle price. The remaining cap value is below the strict debt floor.
- **Confidence:** High — exact historical state transition, pinned archive
  fork execution, current contract views, and upstream invariant source agree.
- **Impact:** The GhostPosition Borrow/Repay/Close ABI and lifecycle are proven
  against real Vesu behavior. Live deployment remains blocked until the
  current-market preflight passes or a separately reviewed market decision is
  made; the test does not justify silently switching pools.

## 2026-09-01 — Canonical Multiply V2 increase and full unwind pass

- **Time:** 2026-09-01T03:05+03:00
- **Source:** Canonical Mainnet Multiply V2 contract and class ABI at block
  `4172487`; `vesuxyz/vesu-v2-periphery` commit
  `3aa1b95af0663cd1fc575cef31ded88816e67277`; GhostLoop Starknet Foundry
  fork test.
- **Finding:** The deployed ABI exactly matches the upstream `PoolKey`, `i129`,
  route, swap, increase/decrease parameters, action enum, and response layout.
  GhostPosition called canonical Multiply as the Vesu position owner, delegated
  only that pinned contract, and used a contract-constructed one-hop ETH/USDC
  Ekubo route. Starting with 0.02 ETH margin, the test borrowed and swapped 20
  USDC into additional collateral, observed both Vesu collateral and debt grow,
  then used `close_position: true` to swap collateral for the exact debt and
  fully unwind. Final Vesu shares, nominal debt, collateral assets, and debt
  assets were all zero; residual ETH returned to the anonymizer identity. The
  capability nonces advanced exactly from 0 through 1.
- **Confidence:** High — pinned upstream source, live deployed ABI, and an
  end-to-end archive-fork execution against canonical Prime, Multiply V2,
  Ekubo, ETH, and USDC agree.
- **Impact:** The remaining contract lifecycle proof is complete. Production
  is still blocked by the current Prime ETH/USDC cap, independent review, real
  Wallet API prepare dry-runs, and encrypted client capability-key handling.

## Research queue

- Serialize each helper enum variant into Wallet API actions and execute a real
  `strk20PrepareInvoke(..., true)` dry-run with a supporting wallet.
- Implement encrypted client-side capability-key storage and recovery warnings.
- Execute the native Shadow Account Wallet API probe if a newer Ready release
  advertises support.

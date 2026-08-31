# GhostLoop Design Decision Request

> **Resolved 2026-08-31:** Semih approved Option B with a mandatory
> `PositionExecutor` migration boundary and minimal allowlisted contracts.

## Decision
Decide whether GhostLoop waits for native Wallet API Shadow Accounts or implements a per-position GhostPosition contract controlled through ordinary STRK20 `privacy_invoke`.

## Current implementation state
The public repository and sprint registration PR are live. STRK20/Vesu/Ekubo sources and Mainnet addresses are pinned, the Vesu Prime ETH/USDC market and canonical Multiply V2 deployment are verified, and no irreversible application or contract architecture has been implemented.

## What I verified
The Wallet API specification at `starkware-libs/starknet-specs` commit `1e79af61071a77e0031d397e1fbe81e9a0637072` describes Shadow Account methods, but current builder guidance says the dapp Wallet API route is pending. `strk20-by-example.org/llms-full.txt`, sprint `IDEAS.md` at `4df40a2f58146d5d6738502b335809db04a5fa72`, and starter kit commit `187fe789dd4f5de14ccb0953abfdb49a26643664` agree. Installed Ready X `5.33.9` dispatches ordinary STRK20 Wallet API methods but has neither `wallet_strk20ShadowAccountCommitment` nor `shadow_account_invoke`. A runtime GUI probe was blocked by browser-URL safety enforcement before any wallet request. Vesu Prime `0x451fe483d5921a2919ddd81d0de6696669bccdacd859f72a4fba7656b97c3b5` and Multiply V2 `0x7964760e90baa28841ec94714151e03fbc13321797e68a874e88f27c9d58513` are live on Mainnet.

## Option A
Wait for Ready/current wallets to expose native Shadow Account Wallet API execution, then use one official Shadow Account per GhostLoop position.

Advantages:
Minimal custom security surface; wallet retains privacy keys; matches the preferred upstream architecture; native per-position identity and collection semantics.

Disadvantages:
The required dapp API is not shipped in the installed wallet or current builder stack; delivery timing is outside our control; core lifecycle work cannot complete before support arrives.

Risks:
Missing the September 7 deadline with no working Mainnet product; late wallet schema or behavior changes; no time left for end-to-end testing after rollout.

Estimated code impact:
Lower contract code, but the critical path remains blocked. Once available: wallet capability adapter, Shadow Account action builders, Vesu lifecycle integration, and tests.

## Option B
Implement an audited-minimum GhostLoop anonymizer plus one GhostPosition contract per position. The position owns Vesu state and accepts actions authorized by a per-position public key, typed signature, monotonic nonce, chain ID, contract address, action/parameters hash, and deadline; ordinary STRK20 `privacy_invoke` funds and settles assets.

Advantages:
Buildable with the Wallet API functionality Ready exposes today; preserves pseudonymous Vesu ownership; supports future repay and unwind; does not wait on wallet rollout.

Disadvantages:
Adds Cairo contracts, client-side position-key management, deployment, testing, and explicit recovery/backup UX; cannot claim official Shadow Account primitives.

Risks:
Signature or replay bugs could lose Mainnet funds; compromised local position keys expose a position; custom anonymizer accounting could strand funds; the larger scope compresses audit time.

Estimated code impact:
One factory/anonymizer, a minimal GhostPosition account-like contract, typed authorization and replay protection, client key storage, Borrow/Multiply/unwind call builders, unit/fork/integration tests, and security documentation.

## My recommendation
Choose Option B because the current dapp Wallet API path is explicitly unavailable and waiting makes a working Mainnet submission depend on an uncommitted third-party release. Keep values minimal, constrain callable targets/selectors, and do not deploy value-bearing contracts until authorization and lifecycle tests pass.

## Question for ChatGPT
Given the verified absence of native Shadow Account execution in Ready 5.33.9 and the September 7 deadline, should GhostLoop proceed with Option B's per-position signed GhostPosition architecture, accepting its additional key-management and Cairo security surface, or pause the product until Option A ships?

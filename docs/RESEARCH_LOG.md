# Research Log

Research entries pin exact source versions and distinguish verified evidence
from assumptions. Times are recorded in UTC.

## 2026-08-31 — STRK20 Private Sprint rules and repository schema

- **Time:** 2026-08-31T19:00Z
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

## Research queue

- Pin `starkware-libs/starknet-privacy` and identify live Mainnet addresses.
- Pin `starkware-libs/starknet-specs` and current Shadow Account Wallet API.
- Test the active privacy wallet's supported methods and action execution.
- Pin Vesu V2 and periphery source; read `multiply.cairo` in full.
- Verify Vesu ETH/USDC Mainnet pair configuration from source and chain state.
- Verify or reject a canonical Vesu Multiply Mainnet deployment.
- Pin Ekubo contracts and verify quote/route semantics used by Multiply.

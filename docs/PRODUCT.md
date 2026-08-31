# Product

## Positioning

**GhostLoop — Private leverage and borrowing on Vesu.**

Open, manage, and unwind Vesu debt positions without linking them to your
public wallet.

GhostLoop is not a lending protocol. It composes STRK20 private balances and
execution identities with Vesu's live lending markets and Ekubo liquidity.

## MVP scope

The MVP is deliberately limited to ETH collateral and USDC debt:

- Open, view, repay, and close a private-linkage borrow position.
- Open a safe 1.5x, 2.0x, or 2.5x leveraged ETH position when current Vesu risk
  parameters permit it.
- Fully unwind leverage, repay debt, and return residual ETH to STRK20.
- Explain precisely what is private and what remains public.

## User experience

The normal user should choose between two simple actions:

```text
Deposit ETH

Borrow USDC
or
Select target leverage

[ Open Position ]
```

Later, the user can repay/close a borrow or select:

```text
[ Unwind Position ]
```

## Privacy promise

GhostLoop targets owner/linkage privacy: a Vesu position should be owned by a
per-position pseudonymous execution account rather than by the user's public
wallet.

The position itself is not invisible. Its account address, collateral, debt,
health, swaps, transaction timing, and other onchain state remain public.
Timing and amount correlation are known limitations.

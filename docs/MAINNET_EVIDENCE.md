# Mainnet Evidence

No Mainnet transaction is claimed yet.

Each submitted transaction must:

1. execute successfully on Starknet Mainnet;
2. touch the canonical STRK20 pool at
   `0x040337b1af3c663e86e333bab5a4b28da8d4652a15a69beee2b677776ffe812a`;
3. contribute to the Borrow, Multiply, or full-unwind product story; and
4. pass `npm run verify:tx -- <TRANSACTION_HASH>`.

Run `npm run evidence` to render the current `strk20.json` transaction list as
Markdown. Empty arrays are intentional until real evidence exists.

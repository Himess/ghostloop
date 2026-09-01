import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import {
  CairoCustomEnum,
  Contract,
  type Abi,
  type STRK20_ACTION,
} from "starknet";

import {
  borrowActions,
  closeBorrowActions,
  createAndFundActions,
  increaseLeverageActions,
  repayActions,
  unwindActions,
  type GhostLoopActionContext,
} from "../src/execution/ghostloop-wallet-actions.js";
import type { Felt } from "../src/execution/position-executor.js";

const felt = (value: number | bigint): Felt => `0x${value.toString(16)}`;
const context: GhostLoopActionContext = {
  anonymizer: felt(0xa),
  userAddress: felt(0xb),
  capabilityPublicKey: felt(0xc),
  positionSalt: felt(0xd),
  authorization: {
    nonce: 7n,
    deadline: 8n,
    signatureR: felt(0xe),
    signatureS: felt(0xf),
  },
};
const eth = felt(1);
const usdc = felt(2);
const auth = ["0x7", "0x8", "0xe", "0xf"];
const openNoteIds = [felt(0x123), felt(0x456)];

const artifact = JSON.parse(
  await readFile(
    resolve(
      "contracts/target/dev/ghostloop_contracts_GhostLoopAnonymizer.contract_class.json",
    ),
    "utf8",
  ),
) as { abi: Abi };
const anonymizerContract = new Contract({
  abi: artifact.abi,
  address: context.anonymizer,
});
const cairoAuthorization = {
  nonce: context.authorization.nonce,
  deadline: context.authorization.deadline,
  signature_r: context.authorization.signatureR,
  signature_s: context.authorization.signatureS,
};

function operation(variant: string, value: object): CairoCustomEnum {
  return new CairoCustomEnum({ [variant]: value });
}

function invokeCalldata(
  actions: STRK20_ACTION[],
  resolvedOpenNoteIds: Felt[] = [],
): string[] {
  const invokeAction = actions.find((action) => action.type === "invoke");
  assert.ok(invokeAction, "action sequence must contain an invoke");

  return invokeAction.calldata.map((item) => {
    const match = /^\$\{openNoteIds\[(\d+)]}$/.exec(item);
    if (!match) return item;

    const noteId = resolvedOpenNoteIds[Number(match[1])];
    assert.ok(noteId, `missing test note ID for ${item}`);
    return noteId;
  });
}

function canonical(values: readonly string[]): string[] {
  return values.map((value) => BigInt(value).toString());
}

function assertMatchesCompiledAbi(
  actions: STRK20_ACTION[],
  tokenIn: Felt,
  tokenOut: Felt,
  amount: bigint,
  operationValue: CairoCustomEnum,
  resolvedOpenNoteIds: Felt[] = [],
) {
  const populated = anonymizerContract.populate("privacy_invoke", {
    in_token: tokenIn,
    out_token: tokenOut,
    amount,
    operation: operationValue,
  });
  assert.ok(
    Array.isArray(populated.calldata),
    "starknet.js must return compiled calldata",
  );
  assert.deepEqual(
    canonical(invokeCalldata(actions, resolvedOpenNoteIds)),
    canonical(populated.calldata.map(String)),
    "Wallet API calldata drifted from starknet.js compilation of the Cairo ABI",
  );
}

const createAndFund = createAndFundActions(context, eth, 3n);
assert.deepEqual(createAndFund, [
  {
    type: "invoke",
    contract: "0xa",
    calldata: ["0x1", "0x1", "0x3", "0x0", "0x0", "0xc", "0xd", ...auth],
  },
]);
assertMatchesCompiledAbi(
  createAndFund,
  eth,
  eth,
  3n,
  operation("CreateAndFund", {
    capability_public_key: context.capabilityPublicKey,
    position_salt: context.positionSalt,
    authorization: cairoAuthorization,
  }),
);

const borrow = borrowActions(context, eth, usdc, 3n, 4n, 5n);
assert.deepEqual(borrow, [
  { type: "transfer", token: "0x2", amount: "OPEN", recipient: "0xb" },
  {
    type: "invoke",
    contract: "0xa",
    calldata: [
      "0x1",
      "0x2",
      "0x3",
      "0x0",
      "0x1",
      "0xc",
      "0xd",
      "0x4",
      "0x0",
      "0x5",
      "0x0",
      "${openNoteIds[0]}",
      ...auth,
    ],
  },
]);
assertMatchesCompiledAbi(
  borrow,
  eth,
  usdc,
  3n,
  operation("Borrow", {
    capability_public_key: context.capabilityPublicKey,
    position_salt: context.positionSalt,
    debt_amount: 4n,
    minimum_borrowed: 5n,
    note_id: openNoteIds[0],
    authorization: cairoAuthorization,
  }),
  openNoteIds,
);

const repay = repayActions(context, usdc, 3n);
assert.deepEqual(repay[0], {
  type: "invoke",
  contract: "0xa",
  calldata: ["0x2", "0x2", "0x3", "0x0", "0x2", "0xc", "0xd", ...auth],
});
assertMatchesCompiledAbi(
  repay,
  usdc,
  usdc,
  3n,
  operation("Repay", {
    capability_public_key: context.capabilityPublicKey,
    position_salt: context.positionSalt,
    authorization: cairoAuthorization,
  }),
);

const closeWithRefund = closeBorrowActions(context, eth, usdc, 3n, true);
assert.equal(closeWithRefund.length, 3);
assert.deepEqual(closeWithRefund[2], {
  type: "invoke",
  contract: "0xa",
  calldata: [
    "0x2",
    "0x1",
    "0x3",
    "0x0",
    "0x3",
    "0xc",
    "0xd",
    "${openNoteIds[0]}",
    "${openNoteIds[1]}",
    ...auth,
  ],
});
assertMatchesCompiledAbi(
  closeWithRefund,
  usdc,
  eth,
  3n,
  operation("CloseBorrow", {
    capability_public_key: context.capabilityPublicKey,
    position_salt: context.positionSalt,
    collateral_note_id: openNoteIds[0],
    debt_refund_note_id: openNoteIds[1],
    authorization: cairoAuthorization,
  }),
  openNoteIds,
);
const closeWithoutRefund = closeBorrowActions(context, eth, usdc, 3n, false);
assert.equal(closeWithoutRefund.length, 2);
assertMatchesCompiledAbi(
  closeWithoutRefund,
  usdc,
  eth,
  3n,
  operation("CloseBorrow", {
    capability_public_key: context.capabilityPublicKey,
    position_salt: context.positionSalt,
    collateral_note_id: openNoteIds[0],
    debt_refund_note_id: 0n,
    authorization: cairoAuthorization,
  }),
  openNoteIds,
);

const increaseLeverage = increaseLeverageActions(context, eth, 3n, 4n, 5n);
assert.deepEqual(increaseLeverage[0], {
  type: "invoke",
  contract: "0xa",
  calldata: [
    "0x1",
    "0x1",
    "0x3",
    "0x0",
    "0x4",
    "0xc",
    "0xd",
    "0x4",
    "0x5",
    ...auth,
  ],
});
assertMatchesCompiledAbi(
  increaseLeverage,
  eth,
  eth,
  3n,
  operation("IncreaseLeverage", {
    capability_public_key: context.capabilityPublicKey,
    position_salt: context.positionSalt,
    debt_amount: 4n,
    minimum_lever_collateral: 5n,
    authorization: cairoAuthorization,
  }),
);

const unwind = unwindActions(context, eth, 1n, 6n, 7n);
assert.deepEqual(unwind, [
  { type: "transfer", token: "0x1", amount: "OPEN", recipient: "0xb" },
  {
    type: "invoke",
    contract: "0xa",
    calldata: [
      "0x1",
      "0x1",
      "0x1",
      "0x0",
      "0x5",
      "0xc",
      "0xd",
      "0x6",
      "0x7",
      "0x0",
      "${openNoteIds[0]}",
      ...auth,
    ],
  },
]);
assertMatchesCompiledAbi(
  unwind,
  eth,
  eth,
  1n,
  operation("Unwind", {
    capability_public_key: context.capabilityPublicKey,
    position_salt: context.positionSalt,
    maximum_collateral_swap: 6n,
    minimum_collateral_returned: 7n,
    collateral_note_id: openNoteIds[0],
    authorization: cairoAuthorization,
  }),
  openNoteIds,
);

assert.throws(
  () => increaseLeverageActions(context, eth, 3n, 1n << 128n, 0n),
  /Cairo integer range/,
);
assert.throws(() => unwindActions(context, eth, 0n, 1n, 1n), /must be non-zero/);
assert.throws(
  () =>
    createAndFundActions(
      { ...context, anonymizer: felt(1n << 252n) },
      eth,
      1n,
    ),
  /felt252 range/,
);

console.log(
  "Wallet actions match starknet.js compilation of the six-operation Cairo ABI, open-note indices, u256 limbs, and u128 input limits.",
);

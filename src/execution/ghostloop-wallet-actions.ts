import type { STRK20_ACTION } from "starknet";

import type { Felt } from "./position-executor.js";

const U64_MAX = (1n << 64n) - 1n;
const U128_MAX = (1n << 128n) - 1n;
const U256_MAX = (1n << 256n) - 1n;
const U128_MASK = U128_MAX;
const FELT_PRIME = (1n << 251n) + 17n * (1n << 192n) + 1n;

/** Must stay in the exact Cairo enum order locked by verify-contract-abi.ts. */
export const GHOSTLOOP_OPERATION = {
  CreateAndFund: 0n,
  Borrow: 1n,
  Repay: 2n,
  CloseBorrow: 3n,
  IncreaseLeverage: 4n,
  Unwind: 5n,
} as const;

export type CapabilityAuthorization = {
  nonce: bigint;
  deadline: bigint;
  signatureR: Felt;
  signatureS: Felt;
};

export type GhostLoopActionContext = {
  anonymizer: Felt;
  userAddress: Felt;
  capabilityPublicKey: Felt;
  positionSalt: Felt;
  authorization: CapabilityAuthorization;
};

function felt(value: bigint | Felt): Felt {
  const parsed = typeof value === "bigint" ? value : BigInt(value);
  if (parsed < 0n || parsed >= FELT_PRIME) {
    throw new RangeError("value is outside the felt252 range");
  }
  return `0x${parsed.toString(16)}`;
}

function bounded(value: bigint, maximum: bigint, name: string): Felt {
  if (value < 0n || value > maximum) {
    throw new RangeError(`${name} is outside its Cairo integer range`);
  }
  return felt(value);
}

function nonZero(value: bigint, name: string): bigint {
  if (value === 0n) throw new RangeError(`${name} must be non-zero`);
  return value;
}

function u256(value: bigint, name: string): [Felt, Felt] {
  if (value < 0n || value > U256_MAX) {
    throw new RangeError(`${name} is outside the u256 range`);
  }
  return [felt(value & U128_MASK), felt(value >> 128n)];
}

function u128(value: bigint, name: string): Felt {
  return bounded(value, U128_MAX, name);
}

function authorization(value: CapabilityAuthorization): Felt[] {
  return [
    bounded(value.nonce, U64_MAX, "authorization nonce"),
    bounded(value.deadline, U64_MAX, "authorization deadline"),
    felt(value.signatureR),
    felt(value.signatureS),
  ];
}

function base(
  tokenIn: Felt,
  tokenOut: Felt,
  amount: bigint,
  operation: bigint,
): Felt[] {
  nonZero(amount, "privacy invoke amount");
  // The pool reads the low felt as its input amount. GhostLoop intentionally
  // limits private inputs to u128 so the u256 high limb is always zero.
  u128(amount, "privacy invoke amount");
  return [
    felt(tokenIn),
    felt(tokenOut),
    ...u256(amount, "privacy invoke amount"),
    felt(operation),
  ];
}

function positionIdentity(context: GhostLoopActionContext): Felt[] {
  return [felt(context.capabilityPublicKey), felt(context.positionSalt)];
}

function invoke(context: GhostLoopActionContext, calldata: string[]): STRK20_ACTION {
  return {
    type: "invoke",
    contract: felt(context.anonymizer),
    calldata,
  };
}

function openNote(index: number): string {
  return `\${openNoteIds[${index}]}`;
}

function openTransfer(token: Felt, recipient: Felt): STRK20_ACTION {
  return {
    type: "transfer",
    token: felt(token),
    amount: "OPEN",
    recipient: felt(recipient),
  };
}

export function createAndFundActions(
  context: GhostLoopActionContext,
  eth: Felt,
  amount: bigint,
): STRK20_ACTION[] {
  return [
    invoke(context, [
      ...base(eth, eth, amount, GHOSTLOOP_OPERATION.CreateAndFund),
      ...positionIdentity(context),
      ...authorization(context.authorization),
    ]),
  ];
}

export function borrowActions(
  context: GhostLoopActionContext,
  eth: Felt,
  usdc: Felt,
  collateralAmount: bigint,
  debtAmount: bigint,
  minimumBorrowed: bigint,
): STRK20_ACTION[] {
  return [
    openTransfer(usdc, context.userAddress),
    invoke(context, [
      ...base(eth, usdc, collateralAmount, GHOSTLOOP_OPERATION.Borrow),
      ...positionIdentity(context),
      ...u256(debtAmount, "debt amount"),
      ...u256(minimumBorrowed, "minimum borrowed"),
      openNote(0),
      ...authorization(context.authorization),
    ]),
  ];
}

export function repayActions(
  context: GhostLoopActionContext,
  usdc: Felt,
  amount: bigint,
): STRK20_ACTION[] {
  return [
    invoke(context, [
      ...base(usdc, usdc, amount, GHOSTLOOP_OPERATION.Repay),
      ...positionIdentity(context),
      ...authorization(context.authorization),
    ]),
  ];
}

export function closeBorrowActions(
  context: GhostLoopActionContext,
  eth: Felt,
  usdc: Felt,
  maximumDebtInput: bigint,
  expectDebtRefund: boolean,
): STRK20_ACTION[] {
  const actions: STRK20_ACTION[] = [openTransfer(eth, context.userAddress)];
  if (expectDebtRefund) actions.push(openTransfer(usdc, context.userAddress));
  actions.push(
    invoke(context, [
      ...base(usdc, eth, maximumDebtInput, GHOSTLOOP_OPERATION.CloseBorrow),
      ...positionIdentity(context),
      openNote(0),
      expectDebtRefund ? openNote(1) : felt(0n),
      ...authorization(context.authorization),
    ]),
  );
  return actions;
}

export function increaseLeverageActions(
  context: GhostLoopActionContext,
  eth: Felt,
  marginAmount: bigint,
  debtAmount: bigint,
  minimumLeverCollateral: bigint,
): STRK20_ACTION[] {
  return [
    invoke(context, [
      ...base(eth, eth, marginAmount, GHOSTLOOP_OPERATION.IncreaseLeverage),
      ...positionIdentity(context),
      u128(nonZero(debtAmount, "debt amount"), "debt amount"),
      u128(minimumLeverCollateral, "minimum lever collateral"),
      ...authorization(context.authorization),
    ]),
  ];
}

export function unwindActions(
  context: GhostLoopActionContext,
  eth: Felt,
  settlementAnchor: bigint,
  maximumCollateralSwap: bigint,
  minimumCollateralReturned: bigint,
): STRK20_ACTION[] {
  return [
    openTransfer(eth, context.userAddress),
    invoke(context, [
      ...base(eth, eth, settlementAnchor, GHOSTLOOP_OPERATION.Unwind),
      ...positionIdentity(context),
      u128(
        nonZero(maximumCollateralSwap, "maximum collateral swap"),
        "maximum collateral swap",
      ),
      ...u256(minimumCollateralReturned, "minimum collateral returned"),
      openNote(0),
      ...authorization(context.authorization),
    ]),
  ];
}

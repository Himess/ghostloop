export type Felt = `0x${string}`;

export type PositionHandle = {
  /** Opaque adapter-owned identifier. Product code must not decode it. */
  reference: string;
  address: Felt;
  executor: "ghost-position" | "native-shadow-account";
};

export type TransactionResult = {
  transactionHash: Felt;
};

export type PositionSnapshot = {
  position: PositionHandle;
  collateralAmount: bigint;
  debtAmount: bigint;
  healthFactor: number | null;
};

export type BorrowRequest = {
  collateralAmount: bigint;
  debtAmount: bigint;
  minimumBorrowedAmount: bigint;
};

export type RepayRequest = {
  amount: bigint;
};

export type CloseBorrowRequest = {
  maximumDebtInput: bigint;
};

export type MultiplyRequest = {
  marginAmount: bigint;
  targetLeverageBps: 15_000 | 20_000 | 25_000;
  minimumCollateralReceived: bigint;
};

export type UnwindRequest = {
  minimumResidualCollateral: bigint;
  maximumDebtInput: bigint;
};

/**
 * Product-facing execution seam.
 *
 * GhostPosition capability keys, deployment calldata, wallet placeholders and
 * future native Shadow Account nonces stay behind this interface.
 */
export interface PositionExecutor {
  createPosition(): Promise<PositionHandle>;
  fundPosition(
    position: PositionHandle,
    amount: bigint,
  ): Promise<TransactionResult>;
  borrow(
    position: PositionHandle,
    request: BorrowRequest,
  ): Promise<TransactionResult>;
  repay(
    position: PositionHandle,
    request: RepayRequest,
  ): Promise<TransactionResult>;
  closeBorrow(
    position: PositionHandle,
    request: CloseBorrowRequest,
  ): Promise<TransactionResult>;
  multiply(
    position: PositionHandle,
    request: MultiplyRequest,
  ): Promise<TransactionResult>;
  unwind(
    position: PositionHandle,
    request: UnwindRequest,
  ): Promise<TransactionResult>;
  settlePrivate(position: PositionHandle): Promise<TransactionResult>;
  readPosition(position: PositionHandle): Promise<PositionSnapshot>;
}

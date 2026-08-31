import type {
  BorrowRequest,
  CloseBorrowRequest,
  MultiplyRequest,
  PositionExecutor,
  PositionHandle,
  PositionSnapshot,
  RepayRequest,
  TransactionResult,
  UnwindRequest,
} from "./position-executor.js";

/**
 * Exact operations the Wallet API/GhostLoopAnonymizer transport may expose.
 * There is intentionally no arbitrary-call method.
 */
export interface GhostPositionGateway {
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

export class GhostPositionExecutor implements PositionExecutor {
  constructor(private readonly gateway: GhostPositionGateway) {}

  createPosition() {
    return this.gateway.createPosition();
  }

  fundPosition(position: PositionHandle, amount: bigint) {
    return this.gateway.fundPosition(position, amount);
  }

  borrow(position: PositionHandle, request: BorrowRequest) {
    return this.gateway.borrow(position, request);
  }

  repay(position: PositionHandle, request: RepayRequest) {
    return this.gateway.repay(position, request);
  }

  closeBorrow(position: PositionHandle, request: CloseBorrowRequest) {
    return this.gateway.closeBorrow(position, request);
  }

  multiply(position: PositionHandle, request: MultiplyRequest) {
    return this.gateway.multiply(position, request);
  }

  unwind(position: PositionHandle, request: UnwindRequest) {
    return this.gateway.unwind(position, request);
  }

  settlePrivate(position: PositionHandle) {
    return this.gateway.settlePrivate(position);
  }

  readPosition(position: PositionHandle) {
    return this.gateway.readPosition(position);
  }
}

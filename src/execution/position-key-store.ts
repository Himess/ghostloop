import type { Felt } from "./position-executor.js";

export type PositionKeyReference = string;

export type CreatedPositionKey = {
  reference: PositionKeyReference;
  publicKey: Felt;
};

/**
 * Capability key custody boundary. Implementations must encrypt before
 * persistence and must never export raw key material to logs or a backend.
 */
export interface PositionKeyStore {
  create(): Promise<CreatedPositionKey>;
  sign(reference: PositionKeyReference, messageHash: Felt): Promise<[Felt, Felt]>;
  exportEncrypted(reference: PositionKeyReference): Promise<Uint8Array>;
  remove(reference: PositionKeyReference): Promise<void>;
}

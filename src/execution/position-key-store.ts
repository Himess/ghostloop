import type { Felt } from "./position-executor.js";

export type PositionKeyReference = string;

export type CreatedPositionKey = {
  reference: PositionKeyReference;
  publicKey: Felt;
};

export interface PositionKeyPersistence {
  get(reference: PositionKeyReference): Promise<Uint8Array | undefined>;
  set(reference: PositionKeyReference, encrypted: Uint8Array): Promise<void>;
  remove(reference: PositionKeyReference): Promise<void>;
}

/**
 * Capability key custody boundary. Implementations must encrypt before
 * persistence and must never export raw key material to logs or a backend.
 */
export interface PositionKeyStore {
  unlock(passphrase: string): Promise<void>;
  lock(): void;
  create(): Promise<CreatedPositionKey>;
  sign(reference: PositionKeyReference, messageHash: Felt): Promise<[Felt, Felt]>;
  exportEncrypted(reference: PositionKeyReference): Promise<Uint8Array>;
  importEncrypted(encrypted: Uint8Array): Promise<CreatedPositionKey>;
  remove(reference: PositionKeyReference): Promise<void>;
}

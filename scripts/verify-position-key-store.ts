import assert from "node:assert/strict";

import { ec } from "starknet";

import type { Felt } from "../src/execution/position-executor.js";
import type {
  PositionKeyPersistence,
  PositionKeyReference,
} from "../src/execution/position-key-store.js";
import { WebCryptoPositionKeyStore } from "../src/execution/webcrypto-position-key-store.js";

const passphrase = "correct horse battery staple";
const messageHash: Felt = "0x123456789";

class MemoryPositionKeyPersistence implements PositionKeyPersistence {
  readonly records = new Map<PositionKeyReference, Uint8Array>();

  async get(reference: PositionKeyReference): Promise<Uint8Array | undefined> {
    return this.records.get(reference)?.slice();
  }

  async set(reference: PositionKeyReference, encrypted: Uint8Array): Promise<void> {
    this.records.set(reference, encrypted.slice());
  }

  async remove(reference: PositionKeyReference): Promise<void> {
    this.records.delete(reference);
  }
}

function verifiesAgainstStarkPublicKey(
  publicKey: Felt,
  message: Felt,
  signatureValues: [Felt, Felt],
): boolean {
  const signature = new ec.starkCurve.Signature(
    BigInt(signatureValues[0]),
    BigInt(signatureValues[1]),
  );
  const x = publicKey.slice(2).padStart(64, "0");
  return (
    ec.starkCurve.verify(signature, message, `02${x}`) ||
    ec.starkCurve.verify(signature, message, `03${x}`)
  );
}

const persistence = new MemoryPositionKeyPersistence();
const store = new WebCryptoPositionKeyStore(persistence);

await assert.rejects(() => store.create(), /locked/);
await assert.rejects(() => store.unlock("too short"), /at least 12 characters/);

await store.unlock(passphrase);
const created = await store.create();
assert.match(created.reference, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
assert.match(created.publicKey, /^0x[0-9a-f]+$/);

const signature = await store.sign(created.reference, messageHash);
assert.ok(
  verifiesAgainstStarkPublicKey(created.publicKey, messageHash, signature),
  "decrypted key must produce a Stark signature for its exported public key",
);

const backup = await store.exportEncrypted(created.reference);
const backupJson = new TextDecoder().decode(backup);
assert.match(backupJson, /"schema":"ghostloop-position-key"/);
assert.match(backupJson, /"name":"AES-GCM"/);
assert.match(backupJson, /"name":"PBKDF2"/);
assert.ok(!backupJson.includes(passphrase));

const wrongPasswordPersistence = new MemoryPositionKeyPersistence();
const wrongPasswordStore = new WebCryptoPositionKeyStore(wrongPasswordPersistence);
await wrongPasswordStore.unlock("this is the wrong password");
await assert.rejects(
  () => wrongPasswordStore.importEncrypted(backup),
  /could not be decrypted/,
);
assert.equal(wrongPasswordPersistence.records.size, 0);

store.lock();
await assert.rejects(() => store.sign(created.reference, messageHash), /locked/);
await assert.rejects(() => store.unlock("too short"), /at least 12 characters/);
await assert.rejects(() => store.sign(created.reference, messageHash), /locked/);
await store.unlock("this is the wrong password");
await assert.rejects(
  () => store.sign(created.reference, messageHash),
  /could not be decrypted/,
);

await store.unlock(passphrase);
const signatureAfterUnlock = await store.sign(created.reference, messageHash);
assert.deepEqual(signatureAfterUnlock, signature);

const recoveredPersistence = new MemoryPositionKeyPersistence();
const recoveredStore = new WebCryptoPositionKeyStore(recoveredPersistence);
await recoveredStore.unlock(passphrase);
const recovered = await recoveredStore.importEncrypted(backup);
assert.deepEqual(recovered, created);
assert.ok(
  verifiesAgainstStarkPublicKey(
    recovered.publicKey,
    messageHash,
    await recoveredStore.sign(recovered.reference, messageHash),
  ),
);
await assert.rejects(
  () => recoveredStore.importEncrypted(backup),
  /already exists/,
);

const tampered = JSON.parse(backupJson) as { publicKey: string };
tampered.publicKey = "0x123";
const tamperedBackup = new TextEncoder().encode(JSON.stringify(tampered));
const tamperedStore = new WebCryptoPositionKeyStore(
  new MemoryPositionKeyPersistence(),
);
await tamperedStore.unlock(passphrase);
await assert.rejects(
  () => tamperedStore.importEncrypted(tamperedBackup),
  /could not be decrypted/,
);

await recoveredStore.remove(recovered.reference);
await assert.rejects(
  () => recoveredStore.sign(recovered.reference, messageHash),
  /not found/,
);

console.log(
  "Position capability keys remain AES-GCM encrypted at rest, sign only while unlocked, and survive authenticated encrypted export/import.",
);

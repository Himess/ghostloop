import { ec } from "starknet";

import type { Felt } from "./position-executor.js";
import type {
  CreatedPositionKey,
  PositionKeyPersistence,
  PositionKeyReference,
  PositionKeyStore,
} from "./position-key-store.js";

const ENVELOPE_SCHEMA = "ghostloop-position-key";
const ENVELOPE_VERSION = 1;
const KDF_ITERATIONS = 600_000;
const MINIMUM_PASSPHRASE_LENGTH = 12;
const MAXIMUM_ENVELOPE_BYTES = 4_096;
const PRIVATE_KEY_BYTES = 32;
const SALT_BYTES = 16;
const IV_BYTES = 12;
const RECORD_PREFIX = "position:";
const FELT_PRIME = (1n << 251n) + 17n * (1n << 192n) + 1n;

type PositionKeyEnvelope = {
  schema: typeof ENVELOPE_SCHEMA;
  version: typeof ENVELOPE_VERSION;
  reference: PositionKeyReference;
  publicKey: Felt;
  kdf: {
    name: "PBKDF2";
    hash: "SHA-256";
    iterations: typeof KDF_ITERATIONS;
    salt: string;
  };
  cipher: {
    name: "AES-GCM";
    iv: string;
    ciphertext: string;
  };
};

function recordKey(reference: PositionKeyReference): string {
  return `${RECORD_PREFIX}${reference}`;
}

function canonicalFelt(value: string, name: string): Felt {
  let parsed: bigint;
  try {
    parsed = BigInt(value);
  } catch {
    throw new Error(`${name} is not a felt`);
  }
  if (parsed < 0n || parsed >= FELT_PRIME) {
    throw new Error(`${name} is outside the felt252 range`);
  }
  return `0x${parsed.toString(16)}`;
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function decodeBase64Url(value: string, name: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error(`${name} is not base64url`);
  }
  const standard = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = standard.padEnd(Math.ceil(standard.length / 4) * 4, "=");
  let binary: string;
  try {
    binary = atob(padded);
  } catch {
    throw new Error(`${name} is not base64url`);
  }
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function exactKeys(value: Record<string, unknown>, expected: string[], name: string) {
  const actual = Object.keys(value).sort();
  const canonicalExpected = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(canonicalExpected)) {
    throw new Error(`${name} has unexpected fields`);
  }
}

function parseEnvelope(serialized: Uint8Array): PositionKeyEnvelope {
  if (serialized.byteLength === 0 || serialized.byteLength > MAXIMUM_ENVELOPE_BYTES) {
    throw new Error("encrypted position key has an invalid size");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(serialized));
  } catch {
    throw new Error("encrypted position key is not valid UTF-8 JSON");
  }
  if (!isRecord(parsed)) throw new Error("encrypted position key is not an object");
  exactKeys(
    parsed,
    ["schema", "version", "reference", "publicKey", "kdf", "cipher"],
    "encrypted position key",
  );
  if (parsed.schema !== ENVELOPE_SCHEMA || parsed.version !== ENVELOPE_VERSION) {
    throw new Error("encrypted position key uses an unsupported format");
  }
  if (
    typeof parsed.reference !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      parsed.reference,
    )
  ) {
    throw new Error("encrypted position key reference is invalid");
  }
  if (typeof parsed.publicKey !== "string") {
    throw new Error("encrypted position key public key is invalid");
  }
  const publicKey = canonicalFelt(parsed.publicKey, "capability public key");

  if (!isRecord(parsed.kdf)) throw new Error("encrypted position key KDF is invalid");
  exactKeys(parsed.kdf, ["name", "hash", "iterations", "salt"], "KDF");
  if (
    parsed.kdf.name !== "PBKDF2" ||
    parsed.kdf.hash !== "SHA-256" ||
    parsed.kdf.iterations !== KDF_ITERATIONS ||
    typeof parsed.kdf.salt !== "string"
  ) {
    throw new Error("encrypted position key KDF is unsupported");
  }
  const salt = decodeBase64Url(parsed.kdf.salt, "KDF salt");
  if (salt.byteLength !== SALT_BYTES) throw new Error("KDF salt has an invalid size");

  if (!isRecord(parsed.cipher)) {
    throw new Error("encrypted position key cipher is invalid");
  }
  exactKeys(parsed.cipher, ["name", "iv", "ciphertext"], "cipher");
  if (
    parsed.cipher.name !== "AES-GCM" ||
    typeof parsed.cipher.iv !== "string" ||
    typeof parsed.cipher.ciphertext !== "string"
  ) {
    throw new Error("encrypted position key cipher is unsupported");
  }
  const iv = decodeBase64Url(parsed.cipher.iv, "cipher IV");
  if (iv.byteLength !== IV_BYTES) throw new Error("cipher IV has an invalid size");
  const ciphertext = decodeBase64Url(parsed.cipher.ciphertext, "ciphertext");
  if (ciphertext.byteLength !== PRIVATE_KEY_BYTES + 16) {
    throw new Error("ciphertext has an invalid size");
  }

  return {
    schema: ENVELOPE_SCHEMA,
    version: ENVELOPE_VERSION,
    reference: parsed.reference,
    publicKey,
    kdf: {
      name: "PBKDF2",
      hash: "SHA-256",
      iterations: KDF_ITERATIONS,
      salt: encodeBase64Url(salt),
    },
    cipher: {
      name: "AES-GCM",
      iv: encodeBase64Url(iv),
      ciphertext: encodeBase64Url(ciphertext),
    },
  };
}

function serializeEnvelope(envelope: PositionKeyEnvelope): Uint8Array {
  return new TextEncoder().encode(JSON.stringify(envelope));
}

function authenticatedData(envelope: PositionKeyEnvelope): Uint8Array {
  return new TextEncoder().encode(
    `${ENVELOPE_SCHEMA}:${ENVELOPE_VERSION}:${envelope.reference}:${envelope.publicKey}`,
  );
}

function randomBytes(crypto: Crypto, length: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(length));
}

function webCryptoBuffer(bytes: Uint8Array): ArrayBuffer {
  if (!(bytes.buffer instanceof ArrayBuffer)) {
    throw new Error("SharedArrayBuffer is not accepted for key material");
  }
  if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
    return bytes.buffer;
  }
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function publicKeyFor(privateKey: Uint8Array): Felt {
  return canonicalFelt(ec.starkCurve.getStarkKey(privateKey), "capability public key");
}

export class WebCryptoPositionKeyStore implements PositionKeyStore {
  private passwordKeyMaterial?: CryptoKey;

  constructor(
    private readonly persistence: PositionKeyPersistence,
    private readonly crypto: Crypto = globalThis.crypto,
  ) {
    if (!crypto?.subtle) throw new Error("WebCrypto is unavailable");
  }

  async unlock(passphrase: string): Promise<void> {
    this.lock();
    if (passphrase.length < MINIMUM_PASSPHRASE_LENGTH) {
      throw new Error(
        `position-key passphrase must be at least ${MINIMUM_PASSPHRASE_LENGTH} characters`,
      );
    }
    const encoded = new TextEncoder().encode(passphrase);
    try {
      this.passwordKeyMaterial = await this.crypto.subtle.importKey(
        "raw",
        encoded,
        "PBKDF2",
        false,
        ["deriveKey"],
      );
    } finally {
      encoded.fill(0);
    }
  }

  lock(): void {
    this.passwordKeyMaterial = undefined;
  }

  async create(): Promise<CreatedPositionKey> {
    this.assertUnlocked();
    const reference = this.crypto.randomUUID();
    const privateKey = ec.starkCurve.utils.randomPrivateKey();
    try {
      const publicKey = publicKeyFor(privateKey);
      const envelope = await this.encrypt(reference, publicKey, privateKey);
      await this.persistence.set(recordKey(reference), serializeEnvelope(envelope));
      return { reference, publicKey };
    } finally {
      privateKey.fill(0);
    }
  }

  async sign(
    reference: PositionKeyReference,
    messageHash: Felt,
  ): Promise<[Felt, Felt]> {
    const envelope = await this.load(reference);
    const privateKey = await this.decrypt(envelope);
    try {
      const canonicalHash = canonicalFelt(messageHash, "authorization message hash");
      const signature = ec.starkCurve.sign(canonicalHash, privateKey);
      return [
        canonicalFelt(`0x${signature.r.toString(16)}`, "signature r"),
        canonicalFelt(`0x${signature.s.toString(16)}`, "signature s"),
      ];
    } finally {
      privateKey.fill(0);
    }
  }

  async exportEncrypted(reference: PositionKeyReference): Promise<Uint8Array> {
    const serialized = await this.persistence.get(recordKey(reference));
    if (!serialized) throw new Error("position key was not found");
    parseEnvelope(serialized);
    return serialized.slice();
  }

  async importEncrypted(encrypted: Uint8Array): Promise<CreatedPositionKey> {
    this.assertUnlocked();
    const envelope = parseEnvelope(encrypted);
    if (await this.persistence.get(recordKey(envelope.reference))) {
      throw new Error("position key reference already exists");
    }

    const privateKey = await this.decrypt(envelope);
    privateKey.fill(0);
    await this.persistence.set(recordKey(envelope.reference), serializeEnvelope(envelope));
    return { reference: envelope.reference, publicKey: envelope.publicKey };
  }

  async remove(reference: PositionKeyReference): Promise<void> {
    await this.persistence.remove(recordKey(reference));
  }

  private assertUnlocked(): CryptoKey {
    if (!this.passwordKeyMaterial) throw new Error("position-key store is locked");
    return this.passwordKeyMaterial;
  }

  private async deriveEncryptionKey(salt: Uint8Array): Promise<CryptoKey> {
    return this.crypto.subtle.deriveKey(
      {
        name: "PBKDF2",
        hash: "SHA-256",
        iterations: KDF_ITERATIONS,
        salt: webCryptoBuffer(salt),
      },
      this.assertUnlocked(),
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"],
    );
  }

  private async encrypt(
    reference: PositionKeyReference,
    publicKey: Felt,
    privateKey: Uint8Array,
  ): Promise<PositionKeyEnvelope> {
    const salt = randomBytes(this.crypto, SALT_BYTES);
    const iv = randomBytes(this.crypto, IV_BYTES);
    const envelope: PositionKeyEnvelope = {
      schema: ENVELOPE_SCHEMA,
      version: ENVELOPE_VERSION,
      reference,
      publicKey,
      kdf: {
        name: "PBKDF2",
        hash: "SHA-256",
        iterations: KDF_ITERATIONS,
        salt: encodeBase64Url(salt),
      },
      cipher: { name: "AES-GCM", iv: encodeBase64Url(iv), ciphertext: "" },
    };
    try {
      const key = await this.deriveEncryptionKey(salt);
      const ciphertext = await this.crypto.subtle.encrypt(
        {
          name: "AES-GCM",
          iv: webCryptoBuffer(iv),
          additionalData: webCryptoBuffer(authenticatedData(envelope)),
        },
        key,
        webCryptoBuffer(privateKey),
      );
      envelope.cipher.ciphertext = encodeBase64Url(new Uint8Array(ciphertext));
      return envelope;
    } finally {
      salt.fill(0);
      iv.fill(0);
    }
  }

  private async decrypt(envelope: PositionKeyEnvelope): Promise<Uint8Array> {
    const salt = decodeBase64Url(envelope.kdf.salt, "KDF salt");
    const iv = decodeBase64Url(envelope.cipher.iv, "cipher IV");
    const ciphertext = decodeBase64Url(envelope.cipher.ciphertext, "ciphertext");
    try {
      const key = await this.deriveEncryptionKey(salt);
      let decrypted: ArrayBuffer;
      try {
        decrypted = await this.crypto.subtle.decrypt(
          {
            name: "AES-GCM",
            iv: webCryptoBuffer(iv),
            additionalData: webCryptoBuffer(authenticatedData(envelope)),
          },
          key,
          webCryptoBuffer(ciphertext),
        );
      } catch {
        throw new Error("position key could not be decrypted");
      }
      const privateKey = new Uint8Array(decrypted);
      if (
        privateKey.byteLength !== PRIVATE_KEY_BYTES ||
        !ec.starkCurve.utils.isValidPrivateKey(privateKey) ||
        publicKeyFor(privateKey) !== envelope.publicKey
      ) {
        privateKey.fill(0);
        throw new Error("position key does not match its public key");
      }
      return privateKey;
    } finally {
      salt.fill(0);
      iv.fill(0);
      ciphertext.fill(0);
    }
  }

  private async load(reference: PositionKeyReference): Promise<PositionKeyEnvelope> {
    this.assertUnlocked();
    const serialized = await this.persistence.get(recordKey(reference));
    if (!serialized) throw new Error("position key was not found");
    const envelope = parseEnvelope(serialized);
    if (envelope.reference !== reference) {
      throw new Error("position key reference does not match its record");
    }
    return envelope;
  }
}

export class IndexedDbPositionKeyPersistence implements PositionKeyPersistence {
  private databasePromise?: Promise<IDBDatabase>;

  constructor(
    private readonly databaseName = "ghostloop",
    private readonly storeName = "position-keys",
  ) {}

  async get(reference: PositionKeyReference): Promise<Uint8Array | undefined> {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const request = database
        .transaction(this.storeName, "readonly")
        .objectStore(this.storeName)
        .get(reference);
      request.onsuccess = () => {
        const value = request.result;
        resolve(value instanceof Uint8Array ? value.slice() : undefined);
      };
      request.onerror = () => reject(request.error ?? new Error("IndexedDB read failed"));
    });
  }

  async set(reference: PositionKeyReference, encrypted: Uint8Array): Promise<void> {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = database.transaction(this.storeName, "readwrite");
      transaction.objectStore(this.storeName).put(encrypted.slice(), reference);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () =>
        reject(transaction.error ?? new Error("IndexedDB write failed"));
      transaction.onabort = () =>
        reject(transaction.error ?? new Error("IndexedDB write was aborted"));
    });
  }

  async remove(reference: PositionKeyReference): Promise<void> {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = database.transaction(this.storeName, "readwrite");
      transaction.objectStore(this.storeName).delete(reference);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () =>
        reject(transaction.error ?? new Error("IndexedDB delete failed"));
      transaction.onabort = () =>
        reject(transaction.error ?? new Error("IndexedDB delete was aborted"));
    });
  }

  private open(): Promise<IDBDatabase> {
    if (!this.databasePromise) {
      this.databasePromise = new Promise((resolve, reject) => {
        if (!globalThis.indexedDB) {
          reject(new Error("IndexedDB is unavailable"));
          return;
        }
        const request = globalThis.indexedDB.open(this.databaseName, 1);
        request.onupgradeneeded = () => {
          if (!request.result.objectStoreNames.contains(this.storeName)) {
            request.result.createObjectStore(this.storeName);
          }
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error ?? new Error("IndexedDB open failed"));
        request.onblocked = () => reject(new Error("IndexedDB upgrade was blocked"));
      });
    }
    return this.databasePromise;
  }
}

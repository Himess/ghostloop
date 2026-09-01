"use client";

import { useEffect, useMemo, useState } from "react";

import {
  checkPositionPassphrase,
  isKeyBackupReady,
  type KeyBackupGate,
  type PreparedPositionKeyMetadata,
} from "@/src/security/key-backup-policy";

type PreparedBackup = {
  reference: string;
  publicKey: string;
  url: string;
  filename: string;
};

function compactFelt(value: string): string {
  return value.length > 22 ? `${value.slice(0, 11)}…${value.slice(-8)}` : value;
}

export function PositionKeySetup({
  onReadyChange,
}: {
  onReadyChange: (key: PreparedPositionKeyMetadata | null) => void;
}) {
  const [passphrase, setPassphrase] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [lossAcknowledged, setLossAcknowledged] = useState(false);
  const [creating, setCreating] = useState(false);
  const [backup, setBackup] = useState<PreparedBackup | null>(null);
  const [gate, setGate] = useState<KeyBackupGate>({
    keyCreated: false,
    downloadStarted: false,
    storageAcknowledged: false,
  });
  const [message, setMessage] = useState<string | null>(null);
  const passphraseCheck = useMemo(
    () => checkPositionPassphrase(passphrase, confirmation, lossAcknowledged),
    [passphrase, confirmation, lossAcknowledged],
  );
  const ready = isKeyBackupReady(gate);

  useEffect(
    () =>
      onReadyChange(
        ready && backup
          ? { reference: backup.reference, publicKey: backup.publicKey }
          : null,
      ),
    [backup, onReadyChange, ready],
  );
  useEffect(
    () => () => {
      if (backup) URL.revokeObjectURL(backup.url);
    },
    [backup],
  );

  async function createEncryptedBackup() {
    if (!passphraseCheck.valid) {
      setMessage(passphraseCheck.reason);
      return;
    }

    setCreating(true);
    setMessage(null);
    try {
      const { WebCryptoPositionKeyStore, IndexedDbPositionKeyPersistence } =
        await import("@/src/execution/webcrypto-position-key-store");
      const store = new WebCryptoPositionKeyStore(
        new IndexedDbPositionKeyPersistence(),
      );
      const { created, encrypted } = await (async () => {
        await store.unlock(passphrase);
        try {
          const createdKey = await store.create();
          return {
            created: createdKey,
            encrypted: await store.exportEncrypted(createdKey.reference),
          };
        } finally {
          store.lock();
        }
      })();

      if (backup) URL.revokeObjectURL(backup.url);
      const blob = new Blob([Uint8Array.from(encrypted).buffer], {
        type: "application/json",
      });
      const filename = `ghostloop-position-key-${created.reference}.json`;
      setBackup({
        reference: created.reference,
        publicKey: created.publicKey,
        url: URL.createObjectURL(blob),
        filename,
      });
      setGate({
        keyCreated: true,
        downloadStarted: false,
        storageAcknowledged: false,
      });
      setPassphrase("");
      setConfirmation("");
      setMessage("Encrypted key created locally. Download its backup next.");
    } catch {
      setMessage("The encrypted position key could not be created in this browser.");
    } finally {
      setCreating(false);
    }
  }

  return (
    <section className="keySetupPanel" aria-labelledby="key-setup-title">
      <div className="keySetupHeading">
        <div>
          <span className="eyebrow"><span /> RECOVERY GATE</span>
          <h2 id="key-setup-title">Protect position authority before it exists</h2>
        </div>
        <span className={`keyGateStatus ${ready ? "ready" : "blocked"}`}>
          {ready ? "Backup ready" : "Required before creation"}
        </span>
      </div>

      <div className="keyWarning" role="note">
        <span aria-hidden="true">!</span>
        <div>
          <strong>There is no backend recovery.</strong>
          <p>
            A capability key authorizes repay, close, and unwind. Forgetting its passphrase, or losing both browser storage and this encrypted backup, can make those actions impossible.
          </p>
        </div>
      </div>

      {!backup ? (
        <div className="keySetupGrid">
          <label>
            <span>Encryption passphrase</span>
            <input
              type="password"
              autoComplete="new-password"
              value={passphrase}
              onChange={(event) => setPassphrase(event.target.value)}
              placeholder="12+ characters"
            />
          </label>
          <label>
            <span>Confirm passphrase</span>
            <input
              type="password"
              autoComplete="new-password"
              value={confirmation}
              onChange={(event) => setConfirmation(event.target.value)}
              placeholder="Repeat passphrase"
            />
          </label>
          <label className="keyCheckbox">
            <input
              type="checkbox"
              checked={lossAcknowledged}
              onChange={(event) => setLossAcknowledged(event.target.checked)}
            />
            <span>I understand GhostLoop cannot reset or recover this key or passphrase.</span>
          </label>
          <button
            type="button"
            className="keyCreateButton"
            disabled={!passphraseCheck.valid || creating}
            onClick={createEncryptedBackup}
          >
            {creating ? "Encrypting locally…" : "Create encrypted position key"}
          </button>
          {!passphraseCheck.valid && (passphrase || confirmation) ? (
            <p className="keyFieldHint">{passphraseCheck.reason}</p>
          ) : null}
        </div>
      ) : (
        <div className="keyBackupResult">
          <div className="keyIdentity">
            <span className="keyGlyph" aria-hidden="true">◇</span>
            <div>
              <strong>Encrypted capability key</strong>
              <code title={backup.publicKey}>{compactFelt(backup.publicKey)}</code>
              <small>Reference {backup.reference}</small>
            </div>
          </div>
          <a
            className="keyDownload"
            href={backup.url}
            download={backup.filename}
            onClick={() =>
              setGate((current) => ({ ...current, downloadStarted: true }))
            }
          >
            Download encrypted backup ↓
          </a>
          <label className="keyCheckbox finalCheck">
            <input
              type="checkbox"
              checked={gate.storageAcknowledged}
              disabled={!gate.downloadStarted}
              onChange={(event) =>
                setGate((current) => ({
                  ...current,
                  storageAcknowledged: event.target.checked,
                }))
              }
            />
            <span>I downloaded the backup and stored its passphrase separately.</span>
          </label>
        </div>
      )}

      {message || ready ? (
        <p className={`keySetupMessage ${ready ? "success" : ""}`} role="status">
          {ready ? "Recovery gate complete for this future position key." : message}
        </p>
      ) : null}
      <p className="keyCustodyNote">
        AES-256-GCM encrypted · PBKDF2-SHA-256 (600,000 rounds) · raw key never leaves this browser
      </p>
    </section>
  );
}

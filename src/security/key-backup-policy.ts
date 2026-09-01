export const MINIMUM_POSITION_PASSPHRASE_LENGTH = 12;

export type KeyBackupGate = {
  keyCreated: boolean;
  downloadStarted: boolean;
  storageAcknowledged: boolean;
};

export type PreparedPositionKeyMetadata = {
  reference: string;
  publicKey: string;
};

export type PassphraseCheck = {
  valid: boolean;
  reason: string | null;
};

export function checkPositionPassphrase(
  passphrase: string,
  confirmation: string,
  lossAcknowledged: boolean,
): PassphraseCheck {
  if (passphrase.length < MINIMUM_POSITION_PASSPHRASE_LENGTH) {
    return {
      valid: false,
      reason: `Use at least ${MINIMUM_POSITION_PASSPHRASE_LENGTH} characters.`,
    };
  }
  if (passphrase !== confirmation) {
    return { valid: false, reason: "Passphrases do not match." };
  }
  if (!lossAcknowledged) {
    return { valid: false, reason: "Acknowledge the recovery warning first." };
  }
  return { valid: true, reason: null };
}

export function isKeyBackupReady(gate: KeyBackupGate): boolean {
  return gate.keyCreated && gate.downloadStarted && gate.storageAcknowledged;
}

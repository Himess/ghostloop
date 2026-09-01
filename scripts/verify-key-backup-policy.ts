import assert from "node:assert/strict";

import {
  checkPositionPassphrase,
  isKeyBackupReady,
} from "../src/security/key-backup-policy.js";

assert.deepEqual(checkPositionPassphrase("short", "short", true), {
  valid: false,
  reason: "Use at least 12 characters.",
});
assert.deepEqual(checkPositionPassphrase("long enough pass", "different pass", true), {
  valid: false,
  reason: "Passphrases do not match.",
});
assert.deepEqual(checkPositionPassphrase("long enough pass", "long enough pass", false), {
  valid: false,
  reason: "Acknowledge the recovery warning first.",
});
assert.deepEqual(checkPositionPassphrase("long enough pass", "long enough pass", true), {
  valid: true,
  reason: null,
});

assert.equal(
  isKeyBackupReady({
    keyCreated: true,
    downloadStarted: true,
    storageAcknowledged: true,
  }),
  true,
);
for (const gate of [
  { keyCreated: false, downloadStarted: true, storageAcknowledged: true },
  { keyCreated: true, downloadStarted: false, storageAcknowledged: true },
  { keyCreated: true, downloadStarted: true, storageAcknowledged: false },
]) {
  assert.equal(isKeyBackupReady(gate), false);
}

console.log(
  "Position creation stays gated until passphrase policy, encrypted download, and explicit recovery acknowledgement all pass.",
);

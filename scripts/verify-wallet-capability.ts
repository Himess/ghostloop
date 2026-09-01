import assert from "node:assert/strict";

import type { WalletWithStarknetFeatures } from "@starknet-io/get-starknet-wallet-standard/features";
import type { STRK20_ACTION, STRK20_CALL_AND_PROOF } from "starknet";

import {
  connectStrk20Wallet,
  inspectStrk20Wallet,
  prepareStrk20InvokeOnly,
  Strk20WalletError,
} from "../src/wallet/strk20-wallet.js";

function mockWallet(versions: string[], chainId = "0x534e5f4d41494e") {
  const requests: string[] = [];
  const wallet = {
    features: {
      "starknet:walletApi": {
        request: async ({ type }: { type: string }) => {
          requests.push(type);
          if (type === "wallet_supportedWalletApi") return versions;
          if (type === "wallet_requestChainId") return chainId;
          throw new Error(`Unexpected wallet request: ${type}`);
        },
      },
    },
  } as unknown as WalletWithStarknetFeatures;
  return { wallet, requests };
}

const supported = mockWallet(["0.10.2", "0.10.3"]);
assert.deepEqual(await inspectStrk20Wallet(supported.wallet), {
  versions: ["0.10.2", "0.10.3"],
  chainId: "0x534e5f4d41494e",
  supportsStrk20: true,
  isMainnet: true,
});
assert.deepEqual(supported.requests.sort(), [
  "wallet_requestChainId",
  "wallet_supportedWalletApi",
]);
assert.ok(!supported.requests.includes("wallet_strk20Balances"));

const unsupported = await inspectStrk20Wallet(mockWallet(["0.10.2"]).wallet);
assert.equal(unsupported.supportsStrk20, false);
await assert.rejects(
  () => connectStrk20Wallet(mockWallet(["0.10.2"]).wallet),
  (error) => error instanceof Strk20WalletError && error.code === "unsupported",
);

const wrongNetwork = await inspectStrk20Wallet(
  mockWallet(["0.10.3"], "0x534e5f5345504f4c4941").wallet,
);
assert.equal(wrongNetwork.supportsStrk20, true);
assert.equal(wrongNetwork.isMainnet, false);
await assert.rejects(
  () =>
    connectStrk20Wallet(
      mockWallet(["0.10.3"], "0x534e5f5345504f4c4941").wallet,
    ),
  (error) => error instanceof Strk20WalletError && error.code === "wrong-network",
);

const actions = [
  { type: "deposit", token: "0x1", amount: "1" },
] as STRK20_ACTION[];
let simulateFlag: boolean | undefined;
let preparedActions: STRK20_ACTION[] | undefined;
const prepared = { calls: [], proof: [] } as unknown as STRK20_CALL_AND_PROOF;
const result = await prepareStrk20InvokeOnly(
  {
    async strk20PrepareInvoke(receivedActions, simulate) {
      preparedActions = receivedActions;
      simulateFlag = simulate;
      return prepared;
    },
  },
  actions,
);
assert.equal(result, prepared);
assert.equal(preparedActions, actions);
assert.equal(simulateFlag, true);
await assert.rejects(() => prepareStrk20InvokeOnly({ strk20PrepareInvoke: async () => prepared }, []));

console.log(
  "Wallet capability detection uses supportedWalletApi, requires Mainnet, never reads balances, and exposes a simulation-only prepare boundary.",
);

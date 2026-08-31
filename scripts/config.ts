import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { RpcProvider } from "starknet";

export const CHAIN_ID = "SN_MAIN";
export const CHAIN_ID_HEX = "0x534e5f4d41494e";

export const ADDRESSES = {
  strk20Pool:
    "0x040337b1af3c663e86e333bab5a4b28da8d4652a15a69beee2b677776ffe812a",
  vesuPrimePool:
    "0x451fe483d5921a2919ddd81d0de6696669bccdacd859f72a4fba7656b97c3b5",
  vesuMultiplyV2:
    "0x7964760e90baa28841ec94714151e03fbc13321797e68a874e88f27c9d58513",
  ekuboCore:
    "0x00000000000000000000000000000000000000000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b",
  eth: "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
  usdc: "0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8",
} as const;

export const EXPECTED_CLASS_HASHES = {
  strk20Pool:
    "0x67dddd89d80fedadc06b6f160798f94800a4a70164e5a24301cd0d6076b554d",
  vesuPrimePool:
    "0x317ce57b2de4a0c482f0eed58a635d100ac5b4801b38251607dcfa35a4128",
  vesuMultiplyV2:
    "0x2f79e81eacc9a2d01bbbf045b9d8b6a7465f8efd4f72db3543bfe00615fc45e",
} as const;

export const DEFAULT_RPC_URL = "https://rpc.starknet.lava.build";

export function getRpcUrl(): string {
  return process.env.STARKNET_RPC_URL || DEFAULT_RPC_URL;
}

export function getProvider(): RpcProvider {
  return new RpcProvider({ nodeUrl: getRpcUrl() });
}

export function normalizeFelt(value: string): string {
  return `0x${BigInt(value).toString(16)}`;
}

export function isMainModule(metaUrl: string): boolean {
  const entrypoint = process.argv[1];
  return Boolean(entrypoint) && metaUrl === pathToFileURL(resolve(entrypoint)).href;
}

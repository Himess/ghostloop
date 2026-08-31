import { hash, shortString } from "starknet";

import {
  ADDRESSES,
  CHAIN_ID,
  CHAIN_ID_HEX,
  EXPECTED_CLASS_HASHES,
  getProvider,
  getRpcUrl,
  isMainModule,
  normalizeFelt,
} from "./config.js";

type Check = {
  name: string;
  actual: string;
  expected: string;
  ok: boolean;
};

function exactCheck(name: string, actual: string, expected: string): Check {
  let ok: boolean;
  try {
    ok = normalizeFelt(actual) === normalizeFelt(expected);
  } catch {
    ok = actual === expected;
  }

  return {
    name,
    actual,
    expected,
    ok,
  };
}

export async function verifyAddresses() {
  const provider = getProvider();
  const blockNumber = await provider.getBlockNumber();
  const chainId = await provider.getChainId();

  const [strk20ClassHash, primeClassHash, multiplyClassHash] =
    await Promise.all([
      provider.getClassHashAt(ADDRESSES.strk20Pool),
      provider.getClassHashAt(ADDRESSES.vesuPrimePool),
      provider.getClassHashAt(ADDRESSES.vesuMultiplyV2),
    ]);

  const pairConfigRaw = await provider.callContract({
    contractAddress: ADDRESSES.vesuPrimePool,
    entrypoint: "pair_config",
    calldata: [ADDRESSES.eth, ADDRESSES.usdc],
  });

  const poolNameRaw = await provider.callContract({
    contractAddress: ADDRESSES.vesuPrimePool,
    entrypoint: "pool_name",
    calldata: [],
  });

  const multiplyCoreResult = await provider.getStorageAt(
    ADDRESSES.vesuMultiplyV2,
    hash.getSelectorFromName("core"),
    "latest",
  );
  const multiplyCore =
    typeof multiplyCoreResult === "string"
      ? multiplyCoreResult
      : multiplyCoreResult.value;

  const checks = [
    exactCheck("chainId", chainId, CHAIN_ID_HEX),
    exactCheck(
      "STRK20 pool class hash",
      strk20ClassHash,
      EXPECTED_CLASS_HASHES.strk20Pool,
    ),
    exactCheck(
      "Vesu Prime class hash",
      primeClassHash,
      EXPECTED_CLASS_HASHES.vesuPrimePool,
    ),
    exactCheck(
      "Vesu Multiply V2 class hash",
      multiplyClassHash,
      EXPECTED_CLASS_HASHES.vesuMultiplyV2,
    ),
    exactCheck("Multiply Ekubo core", multiplyCore, ADDRESSES.ekuboCore),
  ];

  const result = {
    rpcUrl: getRpcUrl(),
    blockNumber,
    chainName: CHAIN_ID,
    chainId,
    addresses: ADDRESSES,
    checks,
    vesuPrimePoolName: shortString.decodeShortString(poolNameRaw[0]),
    ethUsdcPairConfig: {
      raw: pairConfigRaw,
      maxLtv: pairConfigRaw[0]
        ? Number(BigInt(pairConfigRaw[0])) / 1e18
        : null,
      liquidationFactor: pairConfigRaw[1]
        ? Number(BigInt(pairConfigRaw[1])) / 1e18
        : null,
      debtCapRaw: pairConfigRaw[2]
        ? BigInt(pairConfigRaw[2]).toString(10)
        : null,
    },
    ok: checks.every((check) => check.ok),
  };

  return result;
}

if (isMainModule(import.meta.url)) {
  const result = await verifyAddresses();
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
}

import {
  ADDRESSES,
  getProvider,
  getRpcUrl,
  isMainModule,
  normalizeFelt,
} from "./config.js";

type JsonRecord = Record<string, unknown>;

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null;
}

function collectAddressMatches(
  value: unknown,
  target: string,
  path = "$",
  matches: string[] = [],
): string[] {
  if (typeof value === "string") {
    try {
      if (normalizeFelt(value) === normalizeFelt(target)) matches.push(path);
    } catch {
      // Non-felt strings are intentionally ignored.
    }
    return matches;
  }

  if (Array.isArray(value)) {
    value.forEach((entry, index) =>
      collectAddressMatches(entry, target, `${path}[${index}]`, matches),
    );
  } else if (isRecord(value)) {
    Object.entries(value).forEach(([key, entry]) =>
      collectAddressMatches(entry, target, `${path}.${key}`, matches),
    );
  }

  return matches;
}

export async function inspectMainnetTransaction(transactionHash: string) {
  if (!/^0x[0-9a-f]+$/i.test(transactionHash)) {
    throw new Error(`Invalid Starknet transaction hash: ${transactionHash}`);
  }

  const provider = getProvider();
  const [transaction, receipt] = await Promise.all([
    provider.getTransactionByHash(transactionHash),
    provider.getTransactionReceipt(transactionHash),
  ]);

  let trace: unknown = null;
  let traceError: string | null = null;
  try {
    trace = await provider.getTransactionTrace(transactionHash);
  } catch (error) {
    traceError = error instanceof Error ? error.message : String(error);
  }

  const transactionMatches = collectAddressMatches(
    transaction,
    ADDRESSES.strk20Pool,
  );
  const receiptMatches = collectAddressMatches(receipt, ADDRESSES.strk20Pool);
  const traceMatches = collectAddressMatches(trace, ADDRESSES.strk20Pool);
  const executionMatches = [...receiptMatches, ...traceMatches];
  const receiptRecord = receipt as unknown as JsonRecord;
  const transactionRecord = transaction as unknown as JsonRecord;
  const executionStatus = String(receiptRecord.execution_status ?? "UNKNOWN");

  return {
    rpcUrl: getRpcUrl(),
    transactionHash,
    blockNumber: receiptRecord.block_number ?? null,
    sender: transactionRecord.sender_address ?? null,
    transactionType: transactionRecord.type ?? null,
    finalityStatus: receiptRecord.finality_status ?? null,
    executionStatus,
    touchesStrk20Pool: executionMatches.length > 0,
    successful: executionStatus === "SUCCEEDED",
    evidence: {
      receiptPaths: receiptMatches,
      tracePaths: traceMatches,
      calldataPaths: transactionMatches,
      traceError,
    },
  };
}

if (isMainModule(import.meta.url)) {
  const transactionHash = process.argv[2];
  if (!transactionHash) {
    console.error("Usage: npm run verify:tx -- <STARKNET_MAINNET_TX_HASH>");
    process.exitCode = 2;
  } else {
    const result = await inspectMainnetTransaction(transactionHash);
    console.log(JSON.stringify(result, null, 2));
    if (!result.successful || !result.touchesStrk20Pool) process.exitCode = 1;
  }
}

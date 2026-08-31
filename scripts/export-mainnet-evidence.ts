import { readFile } from "node:fs/promises";

import { inspectMainnetTransaction } from "./verify-mainnet-tx.js";

type Submission = {
  transactions: string[];
  contracts: string[];
  demo_video: string;
  demo_url: string;
};

const submission = JSON.parse(
  await readFile(new URL("../strk20.json", import.meta.url), "utf8"),
) as Submission;

const results = [];
for (const transactionHash of submission.transactions) {
  results.push(await inspectMainnetTransaction(transactionHash));
}

const lines = [
  "# Mainnet Evidence",
  "",
  `Generated: ${new Date().toISOString()}`,
  "",
  `Contracts: ${submission.contracts.length}`,
  `Transactions: ${submission.transactions.length}`,
  "",
];

for (const result of results) {
  lines.push(
    `## ${result.transactionHash}`,
    "",
    `- Block: ${String(result.blockNumber)}`,
    `- Sender: ${String(result.sender)}`,
    `- Execution: ${result.executionStatus}`,
    `- STRK20 pool touched: ${result.touchesStrk20Pool ? "yes" : "no"}`,
    "",
  );
}

if (results.length === 0) {
  lines.push(
    "No transaction hashes have been recorded yet. Do not claim Mainnet evidence until all three required transactions pass verification.",
    "",
  );
}

console.log(lines.join("\n"));

if (
  results.some((result) => !result.successful || !result.touchesStrk20Pool)
) {
  process.exitCode = 1;
}

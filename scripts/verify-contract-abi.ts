import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

type AbiFunction = {
  type: "function";
  name: string;
};

type AbiInterface = {
  type: "interface";
  name: string;
  items: AbiFunction[];
};

type ContractClass = {
  abi: Array<AbiInterface | { type: string; name?: string }>;
};

function isPositionInterface(
  item: ContractClass["abi"][number],
): item is AbiInterface {
  return (
    item.type === "interface" &&
    "items" in item &&
    typeof item.name === "string" &&
    item.name.endsWith("::IGhostPosition")
  );
}

const artifactPath = resolve(
  "contracts/target/dev/ghostloop_contracts_GhostPosition.contract_class.json",
);
const contractClass = JSON.parse(
  await readFile(artifactPath, "utf8"),
) as ContractClass;

const positionInterface = contractClass.abi.find(isPositionInterface);

if (!positionInterface) {
  throw new Error("IGhostPosition was not found in the generated contract ABI");
}

const actual = positionInterface.items
  .filter((item) => item.type === "function")
  .map((item) => item.name)
  .sort();
const expected = [
  "anonymizer",
  "borrow",
  "capability_public_key",
  "close_borrow",
  "next_nonce",
  "read_position",
  "repay",
].sort();

if (JSON.stringify(actual) !== JSON.stringify(expected)) {
  throw new Error(
    `GhostPosition ABI drifted. Expected ${expected.join(", ")}; received ${actual.join(", ")}`,
  );
}

console.log(
  `GhostPosition ABI is minimal: ${actual.length} explicit entry points and no arbitrary-call surface.`,
);

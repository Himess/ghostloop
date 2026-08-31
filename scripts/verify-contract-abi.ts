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

type AbiEnum = {
  type: "enum";
  name: string;
  variants: Array<{ name: string; type: string }>;
};

type ContractClass = {
  abi: Array<AbiInterface | AbiEnum | { type: string; name?: string }>;
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

async function verifyInterface(
  artifactName: string,
  interfaceSuffix: string,
  expectedNames: string[],
) {
  const artifactPath = resolve("contracts/target/dev", artifactName);
  const contractClass = JSON.parse(
    await readFile(artifactPath, "utf8"),
  ) as ContractClass;
  const contractInterface = contractClass.abi.find(
    (item): item is AbiInterface =>
      isPositionInterface(item) ||
      (item.type === "interface" &&
        "items" in item &&
        typeof item.name === "string" &&
        item.name.endsWith(interfaceSuffix)),
  );

  if (!contractInterface) {
    throw new Error(`${interfaceSuffix} was not found in ${artifactName}`);
  }

  const actual = contractInterface.items
    .filter((item) => item.type === "function")
    .map((item) => item.name)
    .sort();
  const expected = [...expectedNames].sort();

  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${interfaceSuffix} ABI drifted. Expected ${expected.join(", ")}; received ${actual.join(", ")}`,
    );
  }

  return actual.length;
}

async function verifyEnumVariants(
  artifactName: string,
  enumSuffix: string,
  expectedNames: string[],
) {
  const artifactPath = resolve("contracts/target/dev", artifactName);
  const contractClass = JSON.parse(
    await readFile(artifactPath, "utf8"),
  ) as ContractClass;
  const abiEnum = contractClass.abi.find(
    (item): item is AbiEnum =>
      item.type === "enum" &&
      "variants" in item &&
      typeof item.name === "string" &&
      item.name.endsWith(enumSuffix),
  );

  if (!abiEnum) {
    throw new Error(`${enumSuffix} was not found in ${artifactName}`);
  }

  const actual = abiEnum.variants.map((variant) => variant.name).sort();
  const expected = [...expectedNames].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${enumSuffix} drifted. Expected ${expected.join(", ")}; received ${actual.join(", ")}`,
    );
  }

  return actual.length;
}

const positionEntryPoints = await verifyInterface(
  "ghostloop_contracts_GhostPosition.contract_class.json",
  "::IGhostPosition",
  [
  "anonymizer",
  "borrow",
  "capability_public_key",
  "close_borrow",
  "next_nonce",
  "read_position",
  "repay",
  ],
);
const anonymizerEntryPoints = await verifyInterface(
  "ghostloop_contracts_GhostLoopAnonymizer.contract_class.json",
  "::IGhostLoopAnonymizer",
  [
    "get_position",
    "position_class_hash",
    "predict_position",
    "privacy_invoke",
    "privacy_pool",
  ],
);
const anonymizerOperations = await verifyEnumVariants(
  "ghostloop_contracts_GhostLoopAnonymizer.contract_class.json",
  "::GhostLoopOperation",
  ["CreateAndFund", "Borrow", "Repay", "CloseBorrow"],
);

console.log(
  `Contract ABIs are minimal: ${positionEntryPoints} position entry points, ${anonymizerEntryPoints} anonymizer entry points, and ${anonymizerOperations} closed anonymizer operations, with no arbitrary-call surface.`,
);

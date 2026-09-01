import type { WalletWithStarknetFeatures } from "@starknet-io/get-starknet-wallet-standard/features";
import {
  compareVersions,
  constants,
  WalletAccountV6,
  walletV6,
  type STRK20_ACTION,
  type STRK20_CALL_AND_PROOF,
} from "starknet";

export const MIN_STRK20_WALLET_API = "0.10.3";
export const PUBLIC_MAINNET_RPC = "https://rpc.starknet.lava.build";

export type Strk20WalletCapability = {
  versions: string[];
  chainId: string;
  supportsStrk20: boolean;
  isMainnet: boolean;
};

export type ConnectedStrk20Wallet = {
  account: {
    prepare(actions: STRK20_ACTION[]): Promise<STRK20_CALL_AND_PROOF>;
  };
  address: string;
  capability: Strk20WalletCapability;
};

export type PrepareOnlyAccount = {
  strk20PrepareInvoke(
    actions: STRK20_ACTION[],
    simulate?: boolean,
  ): Promise<STRK20_CALL_AND_PROOF>;
};

export class Strk20WalletError extends Error {
  constructor(
    public readonly code:
      | "capability-query-failed"
      | "unsupported"
      | "wrong-network"
      | "connection-rejected",
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "Strk20WalletError";
  }
}

function sameFelt(left: string, right: string): boolean {
  try {
    return BigInt(left) === BigInt(right);
  } catch {
    return false;
  }
}

export async function inspectStrk20Wallet(
  wallet: WalletWithStarknetFeatures,
): Promise<Strk20WalletCapability> {
  try {
    const [reportedVersions, chainId] = await Promise.all([
      walletV6.supportedWalletApi(wallet),
      walletV6.requestChainId(wallet),
    ]);
    const versions = reportedVersions.map(String);

    return {
      versions,
      chainId,
      supportsStrk20: versions.some(
        (version) => compareVersions(version, MIN_STRK20_WALLET_API) >= 0,
      ),
      isMainnet: sameFelt(chainId, constants.StarknetChainId.SN_MAIN),
    };
  } catch (error) {
    throw new Strk20WalletError(
      "capability-query-failed",
      "The wallet did not answer the Wallet API capability query.",
      { cause: error },
    );
  }
}

export async function connectStrk20Wallet(
  wallet: WalletWithStarknetFeatures,
): Promise<ConnectedStrk20Wallet> {
  const capability = await inspectStrk20Wallet(wallet);
  if (!capability.supportsStrk20) {
    throw new Strk20WalletError(
      "unsupported",
      `This wallet does not advertise Wallet API ${MIN_STRK20_WALLET_API} or newer.`,
    );
  }
  if (!capability.isMainnet) {
    throw new Strk20WalletError(
      "wrong-network",
      "Switch the wallet to Starknet Mainnet before connecting.",
    );
  }

  try {
    const account = await WalletAccountV6.connect(
      { nodeUrl: PUBLIC_MAINNET_RPC },
      wallet,
    );
    if (!account.address) {
      throw new Error("The wallet returned no account.");
    }

    const connectedChainId = await walletV6.requestChainId(wallet);
    if (!sameFelt(connectedChainId, constants.StarknetChainId.SN_MAIN)) {
      throw new Strk20WalletError(
        "wrong-network",
        "The wallet network changed during connection. Switch back to Starknet Mainnet.",
      );
    }

    return {
      account: {
        prepare: (actions) => prepareStrk20InvokeOnly(account, actions),
      },
      address: account.address,
      capability,
    };
  } catch (error) {
    if (error instanceof Strk20WalletError) throw error;
    throw new Strk20WalletError(
      "connection-rejected",
      "Wallet connection was cancelled or returned no account.",
      { cause: error },
    );
  }
}

export async function prepareStrk20InvokeOnly(
  account: PrepareOnlyAccount,
  actions: STRK20_ACTION[],
): Promise<STRK20_CALL_AND_PROOF> {
  if (actions.length === 0) {
    throw new RangeError("At least one STRK20 action is required for a dry-run.");
  }
  return account.strk20PrepareInvoke(actions, true);
}

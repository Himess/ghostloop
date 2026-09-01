"use client";

import { useEffect, useRef, useState } from "react";

import type { Store } from "@starknet-io/get-starknet-discovery";
import type { WalletWithStarknetFeatures } from "@starknet-io/get-starknet-wallet-standard/features";

import {
  connectStrk20Wallet,
  MIN_STRK20_WALLET_API,
  Strk20WalletError,
} from "@/src/wallet/strk20-wallet";

let sharedDiscoveryStore: Store | null = null;

async function loadDiscoveryStore(): Promise<Store> {
  if (!sharedDiscoveryStore) {
    const { createStore } = await import("@starknet-io/get-starknet-discovery");
    sharedDiscoveryStore = createStore({ eip1193Adapters: [] });
  }
  return sharedDiscoveryStore;
}

function shortAddress(address: string): string {
  return address.length > 15 ? `${address.slice(0, 7)}…${address.slice(-5)}` : address;
}

type Connection = {
  wallet: WalletWithStarknetFeatures;
  address: string;
  version: string;
};

export function WalletConnector() {
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [wallets, setWallets] = useState<readonly WalletWithStarknetFeatures[]>([]);
  const [connectingName, setConnectingName] = useState<string | null>(null);
  const [connection, setConnection] = useState<Connection | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const unsubscribeRef = useRef<(() => void) | null>(null);

  useEffect(() => () => unsubscribeRef.current?.(), []);

  async function discoverWallets() {
    setLoading(true);
    setMessage(null);
    try {
      const store = await loadDiscoveryStore();
      unsubscribeRef.current?.();
      unsubscribeRef.current = store.subscribe(setWallets);
      store._refreshInjectedWallets();
      setWallets(store.getWallets());
    } catch {
      setMessage("Wallet discovery could not start in this browser.");
    } finally {
      setLoading(false);
    }
  }

  async function togglePicker() {
    const nextOpen = !open;
    setOpen(nextOpen);
    if (nextOpen && !connection) await discoverWallets();
  }

  async function connect(wallet: WalletWithStarknetFeatures) {
    setConnectingName(wallet.name);
    setMessage(null);
    try {
      const connected = await connectStrk20Wallet(wallet);
      setConnection({
        wallet,
        address: connected.address,
        version: connected.capability.versions.at(-1) ?? MIN_STRK20_WALLET_API,
      });
      setOpen(false);
    } catch (error) {
      setMessage(
        error instanceof Strk20WalletError
          ? error.message
          : "The wallet connection did not complete.",
      );
    } finally {
      setConnectingName(null);
    }
  }

  async function disconnect() {
    try {
      await connection?.wallet.features["standard:disconnect"].disconnect();
    } finally {
      setConnection(null);
      setMessage(null);
      setOpen(false);
    }
  }

  return (
    <div className="walletConnector">
      <button
        className={`walletButton ${connection ? "walletConnected" : ""}`}
        type="button"
        aria-expanded={open}
        aria-haspopup="dialog"
        onClick={togglePicker}
      >
        {connection ? shortAddress(connection.address) : "Connect privacy wallet"}
      </button>

      {open ? (
        <div className="walletPopover" role="dialog" aria-label="Privacy wallet connection">
          <div className="walletPopoverHeading">
            <div>
              <strong>{connection ? "Privacy wallet connected" : "Choose a Starknet wallet"}</strong>
              <span>Requires STRK20 Wallet API {MIN_STRK20_WALLET_API}+</span>
            </div>
            <button type="button" aria-label="Close wallet picker" onClick={() => setOpen(false)}>
              ×
            </button>
          </div>

          {connection ? (
            <div className="walletConnectionDetails">
              <span className="walletIdentityMark" aria-hidden="true">✓</span>
              <div>
                <strong>{connection.wallet.name}</strong>
                <code>{connection.address}</code>
                <small>Wallet API {connection.version} · Starknet Mainnet</small>
              </div>
              <button type="button" onClick={disconnect}>Disconnect</button>
            </div>
          ) : (
            <>
              <div className="walletList" aria-live="polite">
                {loading ? <p>Checking this browser…</p> : null}
                {!loading && wallets.length === 0 ? (
                  <div className="walletEmpty">
                    <strong>No Starknet wallet detected</strong>
                    <p>Enable a privacy-capable wallet extension, then scan again.</p>
                  </div>
                ) : null}
                {wallets.map((wallet) => (
                  <button
                    type="button"
                    className="walletChoice"
                    key={`${wallet.name}-${wallet.version}`}
                    disabled={connectingName !== null}
                    onClick={() => connect(wallet)}
                  >
                    <span className="walletInitial" aria-hidden="true">
                      {wallet.name.slice(0, 1).toUpperCase()}
                    </span>
                    <span><strong>{wallet.name}</strong><small>Check STRK20 capability</small></span>
                    <span>{connectingName === wallet.name ? "Checking…" : "→"}</span>
                  </button>
                ))}
              </div>
              <div className="walletPopoverFooter">
                <button type="button" onClick={discoverWallets} disabled={loading}>
                  Scan again
                </button>
                <a
                  href="https://strk20-by-example.org/starknet-wallet-api/overview"
                  target="_blank"
                  rel="noreferrer"
                >
                  Wallet requirements ↗
                </a>
              </div>
            </>
          )}

          {message ? <p className="walletMessage" role="status">{message}</p> : null}
          <p className="walletPrivacyNote">
            Capability and network are checked before account access. GhostLoop never asks for a viewing key or reads shielded balances during connection.
          </p>
        </div>
      ) : null}
    </div>
  );
}

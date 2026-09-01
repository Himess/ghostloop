"use client";

import dynamic from "next/dynamic";
import { useState } from "react";

import {
  calculateBorrowRisk,
  calculateMultiplyRisk,
  DEFAULT_RISK_BUFFER,
} from "@/src/risk/position-risk";
import type { PreparedPositionKeyMetadata } from "@/src/security/key-backup-policy";

export type MarketView = {
  blockNumber: number;
  ethPriceUsdc: number;
  maxLtv: number;
  liquidationFactor: number;
  remainingCapUsdc: string | null;
  debtFloorUsdc: number;
  oracleValid: boolean;
  liveBorrowViable: boolean;
  reasons: string[];
};

type Mode = "borrow" | "multiply";

const leveragePresets = [1.5, 2, 2.5] as const;

const WalletConnector = dynamic(
  () => import("@/components/wallet-connector").then((module) => module.WalletConnector),
  {
    ssr: false,
    loading: () => (
      <button className="walletButton" type="button" disabled>
        Loading wallet discovery…
      </button>
    ),
  },
);

const PositionKeySetup = dynamic(
  () => import("@/components/position-key-setup").then((module) => module.PositionKeySetup),
  {
    ssr: false,
    loading: () => <div className="keySetupLoading">Loading local recovery controls…</div>,
  },
);

function numberValue(value: string): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function money(value: number, maximumFractionDigits = 2): string {
  if (!Number.isFinite(value)) return "∞";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits,
  }).format(value);
}

function quantity(value: number, digits = 4): string {
  if (!Number.isFinite(value)) return "∞";
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: digits }).format(value);
}

function percent(value: number): string {
  if (!Number.isFinite(value)) return "—";
  return `${(value * 100).toFixed(1)}%`;
}

function Metric({ label, value, detail }: { label: string; value: string; detail?: string }) {
  return (
    <div className="metric">
      <span className="metricLabel">{label}</span>
      <strong>{value}</strong>
      {detail ? <small>{detail}</small> : null}
    </div>
  );
}

function TokenInput({
  id,
  label,
  token,
  value,
  onChange,
  hint,
}: {
  id: string;
  label: string;
  token: "ETH" | "USDC";
  value: string;
  onChange: (value: string) => void;
  hint: string;
}) {
  return (
    <label className="tokenField" htmlFor={id}>
      <span className="fieldHeading">
        <span>{label}</span>
        <small>{hint}</small>
      </span>
      <span className="tokenInputShell">
        <input
          id={id}
          inputMode="decimal"
          autoComplete="off"
          value={value}
          onChange={(event) => onChange(event.target.value)}
          aria-label={`${label} in ${token}`}
        />
        <span className={`tokenBadge token${token}`}>
          <span className="tokenDot" aria-hidden="true" />
          {token}
        </span>
      </span>
    </label>
  );
}

function Logo() {
  return (
    <span className="logoLockup" aria-label="GhostLoop">
      <span className="logoMark" aria-hidden="true">
        <span />
        <span />
      </span>
      <span>GhostLoop</span>
    </span>
  );
}

export function GhostLoopDashboard({ market }: { market: MarketView | null }) {
  const [mode, setMode] = useState<Mode>("borrow");
  const [collateral, setCollateral] = useState("0.02");
  const [borrowAmount, setBorrowAmount] = useState("20");
  const [multiplyDeposit, setMultiplyDeposit] = useState("0.02");
  const [leverage, setLeverage] = useState<(typeof leveragePresets)[number]>(2);
  const [slippage, setSlippage] = useState("0.50");
  const [preparedPositionKey, setPreparedPositionKey] =
    useState<PreparedPositionKeyMetadata | null>(null);
  const keyBackupReady = preparedPositionKey !== null;

  const marketReady = Boolean(market?.liveBorrowViable && market.oracleValid);
  const ethPrice = market?.ethPriceUsdc ?? 0;
  const maxLtv = market?.maxLtv ?? 0.8;

  const borrowRisk =
    numberValue(collateral) > 0 && ethPrice > 0
      ? calculateBorrowRisk({
          collateralEth: numberValue(collateral),
          debtUsdc: numberValue(borrowAmount),
          ethPriceUsdc: ethPrice,
          maxLtv,
          riskBuffer: DEFAULT_RISK_BUFFER,
        })
      : null;

  const multiplyRisk =
    numberValue(multiplyDeposit) > 0 && ethPrice > 0
      ? calculateMultiplyRisk({
          equityEth: numberValue(multiplyDeposit),
          leverage,
          ethPriceUsdc: ethPrice,
          maxLtv,
          riskBuffer: DEFAULT_RISK_BUFFER,
        })
      : null;

  const inputSafe =
    mode === "borrow"
      ? Boolean(borrowRisk?.withinSafetyBuffer)
      : Boolean(multiplyRisk?.withinSafetyBuffer);
  const actionLabel = !market
    ? "Market data unavailable"
    : !marketReady
      ? "Execution paused by market gate"
      : !inputSafe
        ? "Position exceeds safety buffer"
        : !keyBackupReady
          ? "Complete encrypted key backup"
        : "Connect privacy wallet to continue";

  return (
    <main className="siteShell">
      <header className="topbar">
        <Logo />
        <div className="topbarActions">
          <span className="networkPill">
            <span aria-hidden="true" /> Starknet Mainnet
          </span>
          <WalletConnector />
        </div>
      </header>

      <section className="hero" aria-labelledby="hero-title">
        <div className="eyebrow"><span /> PRIVATE POSITION LAYER</div>
        <h1 id="hero-title">
          Borrow in public markets.
          <br />
          <span>Leave your wallet link behind.</span>
        </h1>
        <p>
          GhostLoop composes STRK20 privacy with Vesu lending. Your wallet keeps
          custody; a capability-bound position contract owns the public DeFi position.
        </p>
        <div className="proofRow" aria-label="Protocol assurances">
          <span>STRK20 private balance</span>
          <span>Canonical Vesu Prime</span>
          <span>Fork-proven lifecycle</span>
        </div>
      </section>

      <section className={`marketGate ${marketReady ? "gateOpen" : "gateClosed"}`}>
        <span className="gateIcon" aria-hidden="true">{marketReady ? "✓" : "!"}</span>
        <div>
          <strong>{marketReady ? "Market execution available" : "Mainnet execution is safely paused"}</strong>
          <p>
            {market
              ? marketReady
                ? "Current Vesu configuration passed the live borrow preflight."
                : `Remaining cap is ${market.remainingCapUsdc ?? "unknown"} USDC while the strict debt floor is about ${quantity(market.debtFloorUsdc, 2)} USDC.`
              : "The Vesu market snapshot could not be verified. No transaction can be prepared."}
          </p>
        </div>
        <span className="blockStamp">
          {market ? `verified block ${market.blockNumber.toLocaleString("en-US")}` : "verification unavailable"}
        </span>
      </section>

      <section className="workspace" aria-label="GhostLoop position builder">
        <div className="builderCard">
          <div className="tabList" role="tablist" aria-label="Position mode">
            <button
              type="button"
              role="tab"
              aria-selected={mode === "borrow"}
              className={mode === "borrow" ? "active" : ""}
              onClick={() => setMode("borrow")}
            >
              Borrow
              <small>ETH → USDC</small>
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mode === "multiply"}
              className={mode === "multiply" ? "active" : ""}
              onClick={() => setMode("multiply")}
            >
              Multiply
              <small>Leveraged ETH</small>
            </button>
          </div>

          {mode === "borrow" ? (
            <div className="builderBody" role="tabpanel">
              <div className="sectionHeading">
                <div>
                  <span className="stepNumber">01</span>
                  <h2>Build a private-linkage borrow</h2>
                </div>
                <span className="previewBadge">Preview</span>
              </div>

              <TokenInput
                id="collateral-amount"
                label="Collateral"
                token="ETH"
                value={collateral}
                onChange={setCollateral}
                hint={borrowRisk ? money(borrowRisk.collateralValueUsdc) : "Live oracle required"}
              />
              <div className="flowConnector" aria-hidden="true"><span>↓</span></div>
              <TokenInput
                id="borrow-amount"
                label="Borrow"
                token="USDC"
                value={borrowAmount}
                onChange={setBorrowAmount}
                hint="Settles to private balance"
              />

              <div className="metricsGrid">
                <Metric label="Collateral value" value={borrowRisk ? money(borrowRisk.collateralValueUsdc) : "—"} />
                <Metric label="Debt" value={`${quantity(numberValue(borrowAmount), 2)} USDC`} />
                <Metric label="LTV" value={borrowRisk ? percent(borrowRisk.ltv) : "—"} detail={`Safety limit ${percent(maxLtv - DEFAULT_RISK_BUFFER)}`} />
                <Metric label="Health factor" value={borrowRisk ? quantity(borrowRisk.healthFactor, 2) : "—"} detail="Vesu max-LTV basis" />
                <Metric label="Liquidation price" value={borrowRisk ? money(borrowRisk.liquidationPriceUsdc) : "—"} />
                <Metric label="Borrow APR" value="Live at approval" detail="Never hard-coded" />
              </div>
            </div>
          ) : (
            <div className="builderBody" role="tabpanel">
              <div className="sectionHeading">
                <div>
                  <span className="stepNumber">01</span>
                  <h2>Build a private leveraged position</h2>
                </div>
                <span className="previewBadge">Preview</span>
              </div>

              <TokenInput
                id="multiply-deposit"
                label="Deposit"
                token="ETH"
                value={multiplyDeposit}
                onChange={setMultiplyDeposit}
                hint={money(numberValue(multiplyDeposit) * ethPrice)}
              />

              <fieldset className="leverageField">
                <legend>Target leverage</legend>
                <div className="leverageOptions">
                  {leveragePresets.map((preset) => {
                    const presetRisk = calculateMultiplyRisk({
                      equityEth: Math.max(numberValue(multiplyDeposit), 0.000001),
                      leverage: preset,
                      ethPriceUsdc: Math.max(ethPrice, 1),
                      maxLtv,
                      riskBuffer: DEFAULT_RISK_BUFFER,
                    });
                    return (
                      <button
                        type="button"
                        key={preset}
                        className={leverage === preset ? "active" : ""}
                        disabled={!presetRisk.withinSafetyBuffer}
                        onClick={() => setLeverage(preset)}
                      >
                        {preset.toFixed(1)}×
                        <small>{percent(presetRisk.targetLtv)} LTV</small>
                      </button>
                    );
                  })}
                </div>
              </fieldset>

              <label className="slippageField" htmlFor="slippage">
                <span>Max slippage</span>
                <span className="slippageInput">
                  <input
                    id="slippage"
                    aria-label="Max slippage"
                    inputMode="decimal"
                    value={slippage}
                    onChange={(event) => setSlippage(event.target.value)}
                  />
                  <span>%</span>
                </span>
              </label>

              <div className="metricsGrid">
                <Metric label="Total ETH exposure" value={multiplyRisk ? `${quantity(multiplyRisk.exposureEth, 5)} ETH` : "—"} />
                <Metric label="Estimated debt" value={multiplyRisk ? `${quantity(multiplyRisk.targetDebtUsdc, 2)} USDC` : "—"} />
                <Metric label="Target LTV" value={multiplyRisk ? percent(multiplyRisk.targetLtv) : "—"} detail={`Safety limit ${percent(maxLtv - DEFAULT_RISK_BUFFER)}`} />
                <Metric label="Health factor" value={multiplyRisk ? quantity(multiplyRisk.healthFactor, 2) : "—"} />
                <Metric label="Liquidation price" value={multiplyRisk ? money(multiplyRisk.liquidationPriceUsdc) : "—"} />
                <Metric label="Ekubo quote" value="At approval" detail={`${quantity(numberValue(slippage), 2)}% max slippage`} />
              </div>
            </div>
          )}

          <div className="actionArea">
            {!inputSafe ? (
              <p className="inputWarning">This preview exceeds GhostLoop&apos;s 10-point LTV safety buffer.</p>
            ) : null}
            <button className="primaryAction" type="button" disabled>
              <span>{actionLabel}</span>
              <span aria-hidden="true">→</span>
            </button>
            <p className="actionFootnote">
              No transaction is prepared while the live market, review, wallet, or key-backup gate is incomplete.
            </p>
          </div>
        </div>

        <aside className="sideRail">
          <div className="marketCard">
            <div className="cardHeading">
              <span>Vesu Prime</span>
              <span className={market?.oracleValid ? "liveDot" : "offlineDot"}>
                {market?.oracleValid ? "oracle valid" : "unverified"}
              </span>
            </div>
            <div className="assetPair">
              <span className="assetStack"><i>Ξ</i><i>$</i></span>
              <div><strong>ETH / USDC</strong><small>Collateral / debt</small></div>
            </div>
            <dl className="marketFacts">
              <div><dt>ETH oracle</dt><dd>{market ? money(market.ethPriceUsdc) : "—"}</dd></div>
              <div><dt>Max LTV</dt><dd>{market ? percent(market.maxLtv) : "—"}</dd></div>
              <div><dt>Risk buffer</dt><dd>10.0 pts</dd></div>
              <div><dt>Liquidation factor</dt><dd>{market ? percent(market.liquidationFactor) : "—"}</dd></div>
            </dl>
            <p className="marketNote">Liquidation eligibility in Vesu V2 is checked against max LTV. The liquidation factor prices liquidator collateral.</p>
          </div>

          <div className="privacyCard">
            <span className="shield" aria-hidden="true">◈</span>
            <h3>What stays private?</h3>
            <p>Your public wallet is not recorded as the owner of the Vesu position.</p>
            <h4>What remains public?</h4>
            <p>The position address, collateral, debt, swaps, health, amount and timing remain visible onchain.</p>
            <a href="https://github.com/Himess/ghostloop/blob/main/docs/SECURITY.md" target="_blank" rel="noreferrer">
              Read the exact privacy model <span aria-hidden="true">↗</span>
            </a>
          </div>
        </aside>
      </section>

      <PositionKeySetup onReadyChange={setPreparedPositionKey} />

      <section className="positionPanel" aria-labelledby="position-title">
        <div className="positionHeading">
          <div><span className="eyebrow"><span /> POSITION</span><h2 id="position-title">Your GhostPosition</h2></div>
          <span className="emptyStatus">Not created</span>
        </div>
        <div className="emptyPosition">
          <div className="emptyGlyph" aria-hidden="true"><span /><span /></div>
          <div>
            <strong>No position exists in this browser.</strong>
            <p>
              {keyBackupReady
                ? "Encrypted key backup is ready. Live preflight, wallet prepare simulation, and user approval are still required."
                : "A position appears only after encrypted key backup, live preflight, wallet prepare simulation, and user approval all succeed."}
            </p>
          </div>
          <div className="positionActions">
            <button type="button" disabled>Repay</button>
            <button type="button" disabled>Close borrow</button>
            <button type="button" disabled>Unwind</button>
          </div>
        </div>
      </section>

      <footer>
        <Logo />
        <p>Experimental, unaudited software. Built for the STRK20 Private Sprint.</p>
        <div>
          <a href="https://github.com/Himess/ghostloop" target="_blank" rel="noreferrer">GitHub ↗</a>
          <a href="https://github.com/Himess/ghostloop/blob/main/docs/RESEARCH_LOG.md" target="_blank" rel="noreferrer">Evidence ↗</a>
        </div>
      </footer>
    </main>
  );
}

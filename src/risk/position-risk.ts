export const DEFAULT_RISK_BUFFER = 0.1;

export type BorrowRiskInput = {
  collateralEth: number;
  debtUsdc: number;
  ethPriceUsdc: number;
  maxLtv: number;
  riskBuffer?: number;
};

export type BorrowRisk = {
  collateralValueUsdc: number;
  ltv: number;
  healthFactor: number;
  liquidationPriceUsdc: number;
  safeMaxLtv: number;
  withinSafetyBuffer: boolean;
};

export type MultiplyRiskInput = {
  equityEth: number;
  leverage: number;
  ethPriceUsdc: number;
  maxLtv: number;
  riskBuffer?: number;
};

export type MultiplyRisk = {
  exposureEth: number;
  targetDebtUsdc: number;
  targetLtv: number;
  healthFactor: number;
  liquidationPriceUsdc: number;
  safeMaxLeverage: number;
  withinSafetyBuffer: boolean;
};

function requireFinite(value: number, name: string, allowZero = false): number {
  if (!Number.isFinite(value) || (allowZero ? value < 0 : value <= 0)) {
    throw new RangeError(`${name} must be ${allowZero ? "non-negative" : "positive"}`);
  }
  return value;
}

function safetyLimit(maxLtv: number, riskBuffer: number): number {
  requireFinite(maxLtv, "max LTV");
  requireFinite(riskBuffer, "risk buffer", true);
  if (maxLtv >= 1 || riskBuffer >= maxLtv) {
    throw new RangeError("risk buffer must leave a max LTV between zero and one");
  }
  return maxLtv - riskBuffer;
}

export function calculateBorrowRisk(input: BorrowRiskInput): BorrowRisk {
  const collateralEth = requireFinite(input.collateralEth, "collateral ETH");
  const debtUsdc = requireFinite(input.debtUsdc, "debt USDC", true);
  const ethPriceUsdc = requireFinite(input.ethPriceUsdc, "ETH price");
  const maxLtv = requireFinite(input.maxLtv, "max LTV");
  const safeMaxLtv = safetyLimit(maxLtv, input.riskBuffer ?? DEFAULT_RISK_BUFFER);
  const collateralValueUsdc = collateralEth * ethPriceUsdc;
  const ltv = debtUsdc / collateralValueUsdc;
  const healthFactor = debtUsdc === 0 ? Number.POSITIVE_INFINITY : maxLtv / ltv;
  const liquidationPriceUsdc = debtUsdc / (collateralEth * maxLtv);

  return {
    collateralValueUsdc,
    ltv,
    healthFactor,
    liquidationPriceUsdc,
    safeMaxLtv,
    withinSafetyBuffer: ltv <= safeMaxLtv,
  };
}

export function calculateMultiplyRisk(input: MultiplyRiskInput): MultiplyRisk {
  const equityEth = requireFinite(input.equityEth, "equity ETH");
  const leverage = requireFinite(input.leverage, "leverage");
  const ethPriceUsdc = requireFinite(input.ethPriceUsdc, "ETH price");
  const maxLtv = requireFinite(input.maxLtv, "max LTV");
  if (leverage < 1) throw new RangeError("leverage cannot be below 1x");

  const safeMaxLtv = safetyLimit(maxLtv, input.riskBuffer ?? DEFAULT_RISK_BUFFER);
  const exposureEth = equityEth * leverage;
  const targetDebtUsdc = equityEth * ethPriceUsdc * (leverage - 1);
  const targetLtv = (leverage - 1) / leverage;
  const healthFactor = targetLtv === 0 ? Number.POSITIVE_INFINITY : maxLtv / targetLtv;
  const liquidationPriceUsdc =
    targetDebtUsdc === 0 ? 0 : targetDebtUsdc / (exposureEth * maxLtv);
  const safeMaxLeverage = 1 / (1 - safeMaxLtv);

  return {
    exposureEth,
    targetDebtUsdc,
    targetLtv,
    healthFactor,
    liquidationPriceUsdc,
    safeMaxLeverage,
    withinSafetyBuffer: leverage <= safeMaxLeverage,
  };
}

export function parseTokenUnits(value: string, decimals: number): bigint {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 255) {
    throw new RangeError("token decimals are invalid");
  }
  const match = /^(0|[1-9]\d*)(?:\.(\d*))?$/.exec(value.trim());
  if (!match) throw new RangeError("token amount is not a positive decimal");
  const fraction = match[2] ?? "";
  if (fraction.length > decimals) {
    throw new RangeError("token amount has too many decimal places");
  }
  const scale = 10n ** BigInt(decimals);
  const whole = BigInt(match[1]);
  const fractional = fraction.padEnd(decimals, "0");
  return whole * scale + BigInt(fractional || "0");
}

export function minimumAfterSlippage(amount: bigint, slippageBps: number): bigint {
  if (amount < 0n) throw new RangeError("quote amount cannot be negative");
  if (!Number.isInteger(slippageBps) || slippageBps < 0 || slippageBps >= 10_000) {
    throw new RangeError("slippage must be an integer from 0 to 9999 basis points");
  }
  return (amount * BigInt(10_000 - slippageBps)) / 10_000n;
}

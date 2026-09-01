import assert from "node:assert/strict";

import {
  calculateBorrowRisk,
  calculateMultiplyRisk,
  minimumAfterSlippage,
  parseTokenUnits,
} from "../src/risk/position-risk.js";

const market = { ethPriceUsdc: 2_500, maxLtv: 0.8, riskBuffer: 0.1 };

for (const [leverage, expectedLtv] of [
  [1, 0],
  [1.5, 1 / 3],
  [2, 0.5],
  [2.5, 0.6],
] as const) {
  const result = calculateMultiplyRisk({ equityEth: 1, leverage, ...market });
  assert.ok(Math.abs(result.targetLtv - expectedLtv) < 1e-12);
  assert.ok(Math.abs(result.exposureEth - leverage) < 1e-12);
  assert.ok(Math.abs(result.targetDebtUsdc - 2_500 * (leverage - 1)) < 1e-9);
}

const safeEdge = calculateMultiplyRisk({
  equityEth: 1,
  leverage: 1 / (1 - 0.7),
  ...market,
});
assert.ok(safeEdge.withinSafetyBuffer);
assert.ok(
  !calculateMultiplyRisk({ equityEth: 1, leverage: safeEdge.safeMaxLeverage + 0.01, ...market })
    .withinSafetyBuffer,
);

const borrow = calculateBorrowRisk({
  collateralEth: 0.02,
  debtUsdc: 20,
  ...market,
});
assert.equal(borrow.collateralValueUsdc, 50);
assert.equal(borrow.ltv, 0.4);
assert.equal(borrow.healthFactor, 2);
assert.equal(borrow.liquidationPriceUsdc, 1_250);
assert.ok(borrow.withinSafetyBuffer);

const roundedOracle = calculateBorrowRisk({
  collateralEth: 1,
  debtUsdc: 1_000_000,
  ethPriceUsdc: 2_448.75911532,
  maxLtv: 0.8,
  riskBuffer: 0.1,
});
assert.ok(Number.isFinite(roundedOracle.liquidationPriceUsdc));
assert.ok(!roundedOracle.withinSafetyBuffer);

assert.equal(parseTokenUnits("1", 18), 1_000_000_000_000_000_000n);
assert.equal(parseTokenUnits("0.000000000000000001", 18), 1n);
assert.equal(parseTokenUnits("20.123456", 6), 20_123_456n);
assert.equal(minimumAfterSlippage(parseTokenUnits("1", 18), 50), 995_000_000_000_000_000n);
assert.throws(() => parseTokenUnits("20.1234567", 6), /too many decimal/);
assert.throws(() => parseTokenUnits("1e3", 18), /positive decimal/);
assert.throws(() => minimumAfterSlippage(1n, 10_000), /slippage/);
assert.throws(
  () => calculateBorrowRisk({ collateralEth: 0, debtUsdc: 1, ...market }),
  /collateral ETH must be positive/,
);

console.log(
  "Risk previews cover 1x/1.5x/2x/2.5x leverage, the safety edge, invalid leverage, oracle precision, and ETH/USDC decimals.",
);

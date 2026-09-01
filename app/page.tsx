import { GhostLoopDashboard, type MarketView } from "@/components/ghostloop-dashboard";
import { preflightVesuMarket } from "@/src/market/vesu-snapshot";

export const dynamic = "force-dynamic";

function ratio18(value: string): number {
  return Number(BigInt(value)) / 1e18;
}

async function loadMarket(): Promise<MarketView | null> {
  try {
    const snapshot = await preflightVesuMarket();
    const collateralPrice = BigInt(snapshot.collateralAsset.oraclePrice18);
    const debtPrice = BigInt(snapshot.debtAsset.oraclePrice18);
    const ethPriceUsdc =
      debtPrice === 0n ? 0 : Number((collateralPrice * 1_000_000n) / debtPrice) / 1_000_000;

    return {
      blockNumber: snapshot.blockNumber,
      ethPriceUsdc,
      maxLtv: ratio18(snapshot.pair.maxLtv18),
      liquidationFactor: ratio18(snapshot.pair.liquidationFactor18),
      remainingCapUsdc: snapshot.pair.remainingCapUsdc,
      debtFloorUsdc: ratio18(snapshot.debtAsset.floorValue18),
      oracleValid:
        snapshot.collateralAsset.oraclePriceValid && snapshot.debtAsset.oraclePriceValid,
      liveBorrowViable: snapshot.liveBorrowViable,
      reasons: snapshot.reasons,
    };
  } catch {
    return null;
  }
}

export default async function HomePage() {
  return <GhostLoopDashboard market={await loadMarket()} />;
}

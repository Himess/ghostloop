import { ADDRESSES, CHAIN_ID, getProvider, getRpcUrl } from "../../scripts/config";

const U128_SHIFT = 128n;

function readU256(raw: string[], index: number): bigint {
  const low = BigInt(raw[index] ?? "0");
  const high = BigInt(raw[index + 1] ?? "0");
  return low + (high << U128_SHIFT);
}

function decimal(raw: bigint, scale: bigint): string {
  if (scale <= 1n) return raw.toString(10);
  const decimals = scale.toString(10).length - 1;
  const whole = raw / scale;
  const fraction = (raw % scale)
    .toString(10)
    .padStart(decimals, "0")
    .replace(/0+$/, "");
  return fraction ? `${whole}.${fraction}` : whole.toString(10);
}

export async function preflightVesuMarket() {
  const provider = getProvider();
  const [
    blockNumber,
    pairConfigRaw,
    pairRaw,
    collateralAssetRaw,
    collateralPriceRaw,
    debtAssetRaw,
    debtPriceRaw,
  ] = await Promise.all([
    provider.getBlockNumber(),
    provider.callContract({
      contractAddress: ADDRESSES.vesuPrimePool,
      entrypoint: "pair_config",
      calldata: [ADDRESSES.eth, ADDRESSES.usdc],
    }),
    provider.callContract({
      contractAddress: ADDRESSES.vesuPrimePool,
      entrypoint: "pairs",
      calldata: [ADDRESSES.eth, ADDRESSES.usdc],
    }),
    provider.callContract({
      contractAddress: ADDRESSES.vesuPrimePool,
      entrypoint: "asset_config",
      calldata: [ADDRESSES.eth],
    }),
    provider.callContract({
      contractAddress: ADDRESSES.vesuPrimePool,
      entrypoint: "price",
      calldata: [ADDRESSES.eth],
    }),
    provider.callContract({
      contractAddress: ADDRESSES.vesuPrimePool,
      entrypoint: "asset_config",
      calldata: [ADDRESSES.usdc],
    }),
    provider.callContract({
      contractAddress: ADDRESSES.vesuPrimePool,
      entrypoint: "price",
      calldata: [ADDRESSES.usdc],
    }),
  ]);

  const maxLtv = BigInt(pairConfigRaw[0] ?? "0");
  const liquidationFactor = BigInt(pairConfigRaw[1] ?? "0");
  const debtCap = BigInt(pairConfigRaw[2] ?? "0");
  const totalNominalDebt = readU256(pairRaw, 2);
  const collateralScale = readU256(collateralAssetRaw, 10);
  const collateralPrice = readU256(collateralPriceRaw, 0);
  const collateralPriceIsValid = BigInt(collateralPriceRaw[2] ?? "0") !== 0n;
  const floorValue = readU256(debtAssetRaw, 8);
  const debtScale = readU256(debtAssetRaw, 10);
  const rateAccumulator = readU256(debtAssetRaw, 14);
  const debtPrice = readU256(debtPriceRaw, 0);
  const debtPriceIsValid = BigInt(debtPriceRaw[2] ?? "0") !== 0n;

  let totalDebt = 0n;
  if (totalNominalDebt !== 0n) {
    const totalDebtRaw = await provider.callContract({
      contractAddress: ADDRESSES.vesuPrimePool,
      entrypoint: "calculate_debt",
      calldata: [
        pairRaw[2] ?? "0",
        pairRaw[3] ?? "0",
        "0",
        debtAssetRaw[14] ?? "0",
        debtAssetRaw[15] ?? "0",
        debtAssetRaw[10] ?? "0",
        debtAssetRaw[11] ?? "0",
      ],
    });
    totalDebt = readU256(totalDebtRaw, 0);
  }

  const unlimitedCap = debtCap === 0n;
  const remainingCap = unlimitedCap || totalDebt >= debtCap ? 0n : debtCap - totalDebt;
  const remainingCapValue =
    unlimitedCap || debtScale === 0n ? 0n : (remainingCap * debtPrice) / debtScale;
  const capAllowsFloorDebt = unlimitedCap || remainingCapValue > floorValue;

  const reasons: string[] = [];
  if (maxLtv === 0n) reasons.push("ETH/USDC max LTV is zero");
  if (!collateralPriceIsValid || collateralPrice === 0n) {
    reasons.push("ETH oracle price is invalid");
  }
  if (!debtPriceIsValid || debtPrice === 0n) reasons.push("USDC oracle price is invalid");
  if (collateralScale === 0n) reasons.push("ETH asset scale is zero");
  if (debtScale === 0n) reasons.push("USDC asset scale is zero");
  if (!capAllowsFloorDebt) {
    reasons.push(
      "remaining ETH/USDC debt cap cannot satisfy Vesu's strict minimum-debt floor",
    );
  }

  const liveBorrowViable = reasons.length === 0;
  return {
    rpcUrl: getRpcUrl(),
    blockNumber,
    chainName: CHAIN_ID,
    pool: ADDRESSES.vesuPrimePool,
    market: { collateral: ADDRESSES.eth, debt: ADDRESSES.usdc },
    pair: {
      maxLtv18: maxLtv.toString(10),
      liquidationFactor18: liquidationFactor.toString(10),
      debtCapRaw: debtCap.toString(10),
      debtCapUsdc: decimal(debtCap, debtScale),
      totalNominalDebt18: totalNominalDebt.toString(10),
      totalDebtRaw: totalDebt.toString(10),
      totalDebtUsdc: decimal(totalDebt, debtScale),
      remainingCapRaw: unlimitedCap ? null : remainingCap.toString(10),
      remainingCapUsdc: unlimitedCap ? null : decimal(remainingCap, debtScale),
    },
    collateralAsset: {
      scale: collateralScale.toString(10),
      oraclePrice18: collateralPrice.toString(10),
      oraclePriceValid: collateralPriceIsValid,
    },
    debtAsset: {
      scale: debtScale.toString(10),
      floorValue18: floorValue.toString(10),
      rateAccumulator18: rateAccumulator.toString(10),
      oraclePrice18: debtPrice.toString(10),
      oraclePriceValid: debtPriceIsValid,
      remainingCapValue18: unlimitedCap ? null : remainingCapValue.toString(10),
    },
    liveBorrowViable,
    reasons,
    historicalFork: {
      activeBlock: 4_172_487,
      disablingBlock: 4_172_488,
      governanceTransaction:
        "0x7881366874d2627df382748a100346f6514856d0ea47fd0c4a22e6c0aad9a9f",
    },
  };
}

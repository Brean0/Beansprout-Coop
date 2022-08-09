import { BigNumber } from "@ethersproject/bignumber";
import { AddressZero } from "@ethersproject/constants";
import { Decimal, Decimalish } from "@liquity/lib-base";

export interface LUSDChickenBondConfig {
  targetAverageAgeSeconds: BigNumber;
  initialAccrualParameter: BigNumber;
  minimumAccrualParameter: BigNumber;
  accrualAdjustmentRate: BigNumber;
  accrualAdjustmentPeriodSeconds: BigNumber;
  chickenInAMMFee: BigNumber;
  curveDepositDydxThreshold: BigNumber;
  curveWithdrawalDxdyThreshold: BigNumber;
  bootstrapPeriodChickenIn: BigNumber;
  bootstrapPeriodRedeem: BigNumber;
  bootstrapPeriodShift: BigNumber;
  shifterDelay: BigNumber;
  shifterWindow: BigNumber;
  minBLUSDSupply: BigNumber;
  minBondAmount: BigNumber;
  nftRandomnessDivisor: BigNumber;
  redemptionFeeBeta: BigNumber;
  redemptionFeeMinuteDecayFactor: BigNumber;
  bondNFTTransferLockoutPeriodSeconds: BigNumber;
  yearnGovernanceAddress: string;

  bLUSDPoolA: BigNumber;
  bLUSDPoolGamma: BigNumber;
  bLUSDPoolMidFee: BigNumber;
  bLUSDPoolOutFee: BigNumber;
  bLUSDPoolAllowedExtraProfit: BigNumber;
  bLUSDPoolFeeGamma: BigNumber;
  bLUSDPoolAdjustmentStep: BigNumber;
  bLUSDPoolAdminFee: BigNumber;
  bLUSDPoolMAHalfTime: BigNumber;
  bLUSDPoolInitialPrice: BigNumber;

  realSecondsPerFakeDay: number;
  lusdFaucetTapAmount: BigNumber;
  lusdFaucetTapPeriod: BigNumber;
  harvesterBAMMAPR: BigNumber;
  harvesterCurveAPR: BigNumber;
}

const SPEED = 24; // Fake days per real day
const DAY = BigNumber.from(24 * 60 * 60).div(SPEED);
const ONE = BigNumber.from(10).pow(18);

const bnFromDecimal = (x: Decimalish) => BigNumber.from(Decimal.from(x).hex);
const curvePercent = (percentage: number) => bnFromDecimal(percentage).div(1e10);

// Half-life of 12h
const REDEMPTION_MINUTE_DECAY = 0.5 ** (60 / DAY.div(2).toNumber());

export const defaultConfig: Readonly<LUSDChickenBondConfig> = {
  targetAverageAgeSeconds: DAY.mul(30),
  initialAccrualParameter: DAY.mul(5).mul(ONE),
  minimumAccrualParameter: DAY.mul(5).mul(ONE).div(1000),
  accrualAdjustmentRate: ONE.div(100),
  accrualAdjustmentPeriodSeconds: DAY,
  chickenInAMMFee: ONE.div(100),
  curveDepositDydxThreshold: ONE,
  curveWithdrawalDxdyThreshold: ONE,
  bootstrapPeriodChickenIn: DAY.mul(7),
  bootstrapPeriodRedeem: DAY.mul(7),
  bootstrapPeriodShift: DAY.mul(90),
  shifterDelay: BigNumber.from(1),
  shifterWindow: BigNumber.from(600),
  minBLUSDSupply: ONE,
  minBondAmount: ONE.mul(100),
  nftRandomnessDivisor: ONE.mul(1000),
  redemptionFeeBeta: BigNumber.from(2),
  redemptionFeeMinuteDecayFactor: bnFromDecimal(REDEMPTION_MINUTE_DECAY),
  bondNFTTransferLockoutPeriodSeconds: DAY,
  yearnGovernanceAddress: AddressZero,

  // bLUSD:LUSD pool params (Curve v2)
  bLUSDPoolA: BigNumber.from(400000),
  bLUSDPoolGamma: bnFromDecimal(0.000145),
  bLUSDPoolMidFee: curvePercent(0.5),
  bLUSDPoolOutFee: curvePercent(1.0),
  bLUSDPoolAllowedExtraProfit: bnFromDecimal(0.000002),
  bLUSDPoolFeeGamma: bnFromDecimal(0.0023),
  bLUSDPoolAdjustmentStep: bnFromDecimal(0.000146),
  bLUSDPoolAdminFee: curvePercent(50),
  bLUSDPoolMAHalfTime: DAY,
  bLUSDPoolInitialPrice: bnFromDecimal(1.2), // (coin0 / coin1)

  // Testnet-specific params
  realSecondsPerFakeDay: DAY.toNumber(),
  lusdFaucetTapAmount: ONE.mul(10000),
  lusdFaucetTapPeriod: DAY,
  harvesterBAMMAPR: ONE.mul(SPEED).div(5),
  harvesterCurveAPR: ONE.mul(SPEED).div(20)
};

const mapConfig = (
  r: Readonly<LUSDChickenBondConfig>,
  f: <K extends keyof LUSDChickenBondConfig>(
    k: K,
    v: LUSDChickenBondConfig[K]
  ) => LUSDChickenBondConfig[K]
) =>
  Object.fromEntries(
    Object.entries(r).map(([k, v]) => [k, f(k as keyof LUSDChickenBondConfig, v)])
  ) as unknown as LUSDChickenBondConfig;

export const fillConfig = (config?: Readonly<Partial<LUSDChickenBondConfig>>) =>
  mapConfig(
    defaultConfig,
    (paramName, defaultValue) => (config && config[paramName]) ?? defaultValue
  );

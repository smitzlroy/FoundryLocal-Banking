/**
 * Shared types and tenor definitions for the rate-forecast dashboard.
 *
 * Each "tenor" (a time horizon for an interest rate) is given a plain-English
 * banking label so non-specialists can read the dashboard. `highlight` marks
 * the few products we surface as headline cards.
 */
export const TENORS = [
  { key: "y_1m", label: "1M", months: 1, product: "Overnight cash", highlight: false },
  { key: "y_3m", label: "3M", months: 3, product: "3-month savings", highlight: false },
  { key: "y_6m", label: "6M", months: 6, product: "6-month savings", highlight: false },
  { key: "y_12m", label: "1Y", months: 12, product: "1-year savings bond", highlight: true },
  { key: "y_24m", label: "2Y", months: 24, product: "2-year fixed mortgage", highlight: true },
  { key: "y_36m", label: "3Y", months: 36, product: "3-year fixed mortgage", highlight: false },
  { key: "y_60m", label: "5Y", months: 60, product: "5-year fixed mortgage", highlight: true },
  { key: "y_84m", label: "7Y", months: 84, product: "7-year loan", highlight: false },
  { key: "y_120m", label: "10Y", months: 120, product: "10-year loan", highlight: true },
] as const;

export type TenorPoint = {
  label: string;
  months: number;
  product: string;
  base: number; // current rate, percent
  forecast: number; // predicted rate, percent
};

/**
 * Where the prediction actually ran:
 *  - "cloud"   : the model service in Azure (Act 1)
 *  - "edge"    : Foundry Local on Azure Local, on-premises (Act 2)
 *  - "offline" : no model reachable, showing built-in sample data
 */
export type ForecastLocation = "cloud" | "edge" | "offline";

export type ForecastResponse = {
  location: ForecastLocation;
  modelId: string;
  latencyMs: number;
  scenarioBps: number;
  curve: TenorPoint[];
  generatedAt: string;
};


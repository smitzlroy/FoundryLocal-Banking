/**
 * Baseline yield curve used as model input and as the mock fallback basis.
 * Values are realistic-ish UK-style annualised yields in percent.
 */
import { TENORS } from "./types";

export const BASE_CURVE_PERCENT: Record<string, number> = {
  y_1m: 4.85,
  y_3m: 4.78,
  y_6m: 4.65,
  y_12m: 4.42,
  y_24m: 4.15,
  y_36m: 4.02,
  y_60m: 3.95,
  y_84m: 4.01,
  y_120m: 4.12,
};

/**
 * Deterministic mock forecaster. Applies a parallel scenario shift plus a mild
 * steepening/flattening response so the dashboard behaves believably without a
 * live edge endpoint. Mirrors the shape of the real ONNX model output.
 */
export function mockForecast(scenarioBps: number): Record<string, number> {
  const out: Record<string, number> = {};
  for (const t of TENORS) {
    const base = BASE_CURVE_PERCENT[t.key];
    const shift = scenarioBps / 100; // bps -> percent
    // Longer tenors react a bit less to short-rate scenario shocks.
    const damping = 1 - Math.min(t.months, 120) / 360;
    out[t.key] = Number((base + shift * damping).toFixed(3));
  }
  return out;
}

"""
Generate a synthetic, regulator-friendly interest-rate dataset for the
banking edge-inference demo.

Why synthetic: no licensing constraints, fully reproducible, and it lets the
demo run in a disconnected / sovereign environment with zero external data
dependencies. The series mimics realistic short-rate dynamics using a
Vasicek-style mean-reverting process plus a yield-curve construction.

Output: model/data/rates.csv with daily observations across multiple tenors.
"""
from __future__ import annotations

import argparse
import os
from datetime import date, timedelta

import numpy as np
import pandas as pd

TENORS_MONTHS = [1, 3, 6, 12, 24, 36, 60, 84, 120]  # 1M .. 10Y


def vasicek_short_rate(
    n: int,
    r0: float,
    kappa: float,
    theta: float,
    sigma: float,
    dt: float,
    rng: np.random.Generator,
) -> np.ndarray:
    """Simulate a Vasicek mean-reverting short rate path."""
    rates = np.empty(n, dtype=np.float64)
    rates[0] = r0
    for t in range(1, n):
        dr = kappa * (theta - rates[t - 1]) * dt + sigma * np.sqrt(dt) * rng.standard_normal()
        rates[t] = max(rates[t - 1] + dr, 0.0)  # floor at zero
    return rates


def build_curve(short_rate: float, level: float, slope: float, curvature: float) -> dict[str, float]:
    """Construct a plausible yield curve from a short rate using a
    Nelson-Siegel style parameterisation across tenors."""
    curve: dict[str, float] = {}
    for m in TENORS_MONTHS:
        tau = m / 12.0
        lam = 0.6
        b1 = (1 - np.exp(-lam * tau)) / (lam * tau)
        b2 = b1 - np.exp(-lam * tau)
        yld = short_rate + level + slope * b1 + curvature * b2
        curve[f"y_{m}m"] = round(float(max(yld, 0.0)), 5)
    return curve


def generate(n_days: int, seed: int) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    short = vasicek_short_rate(
        n=n_days, r0=0.045, kappa=0.15, theta=0.035, sigma=0.012, dt=1 / 252, rng=rng
    )

    start = date.today() - timedelta(days=n_days)
    rows = []
    for i in range(n_days):
        d = start + timedelta(days=i)
        # Slowly varying curve shape factors
        level = 0.005 * np.sin(i / 180.0)
        slope = 0.010 + 0.004 * np.cos(i / 90.0)
        curvature = -0.006 + 0.003 * np.sin(i / 120.0)
        curve = build_curve(short[i], level, slope, curvature)
        rows.append({"date": d.isoformat(), "short_rate": round(float(short[i]), 5), **curve})

    return pd.DataFrame(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate synthetic interest-rate data.")
    parser.add_argument("--days", type=int, default=2520, help="Number of daily observations (~10y).")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed for reproducibility.")
    parser.add_argument(
        "--out",
        default=os.path.join(os.path.dirname(__file__), "data", "rates.csv"),
        help="Output CSV path.",
    )
    args = parser.parse_args()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    df = generate(args.days, args.seed)
    df.to_csv(args.out, index=False)
    print(f"Wrote {len(df)} rows x {df.shape[1]} cols -> {args.out}")
    print(df.tail(3).to_string(index=False))


if __name__ == "__main__":
    main()

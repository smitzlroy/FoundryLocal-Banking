"""
Train a compact interest-rate forecasting model and export it to ONNX.

Approach
--------
We frame next-day yield-curve forecasting as a multi-output regression:
given a window of recent curve observations (flattened features), predict the
full curve for the next day. A gradient-boosted tree ensemble keeps the model
tiny (sub-megabyte), CPU-friendly, and a good fit for Foundry Local's ONNX
Runtime *predictive* workload type on Azure Local.

Why not a giant LLM: interest-rate modeling is fundamentally numeric/predictive.
A small ONNX regressor is faster, cheaper, fully explainable, and ideal for a
sovereign edge deployment.

Output: model/artifacts/rate_forecast.onnx (+ feature metadata json)
"""
from __future__ import annotations

import argparse
import json
import os

import numpy as np
import pandas as pd

TENOR_COLS = [f"y_{m}m" for m in (1, 3, 6, 12, 24, 36, 60, 84, 120)]


def build_windows(df: pd.DataFrame, lookback: int) -> tuple[np.ndarray, np.ndarray]:
    """Create supervised samples: X = flattened last `lookback` curves,
    y = next-day curve."""
    curves = df[TENOR_COLS].to_numpy(dtype=np.float32)
    x_rows, y_rows = [], []
    for i in range(lookback, len(curves)):
        x_rows.append(curves[i - lookback : i].flatten())
        y_rows.append(curves[i])
    return np.asarray(x_rows, dtype=np.float32), np.asarray(y_rows, dtype=np.float32)


def main() -> None:
    parser = argparse.ArgumentParser(description="Train + export ONNX rate forecaster.")
    parser.add_argument(
        "--data",
        default=os.path.join(os.path.dirname(__file__), "data", "rates.csv"),
    )
    parser.add_argument("--lookback", type=int, default=10)
    parser.add_argument(
        "--out-dir",
        default=os.path.join(os.path.dirname(__file__), "artifacts"),
    )
    args = parser.parse_args()

    # Imports kept local so `generate_data.py` can run without ML deps installed.
    from sklearn.ensemble import HistGradientBoostingRegressor
    from sklearn.multioutput import MultiOutputRegressor
    from sklearn.metrics import mean_absolute_error
    from skl2onnx import to_onnx
    from skl2onnx.common.data_types import FloatTensorType

    df = pd.read_csv(args.data)
    x, y = build_windows(df, args.lookback)

    split = int(len(x) * 0.85)
    x_train, x_test = x[:split], x[split:]
    y_train, y_test = y[:split], y[split:]

    base = HistGradientBoostingRegressor(max_depth=4, max_iter=200, learning_rate=0.05)
    model = MultiOutputRegressor(base)
    model.fit(x_train, y_train)

    preds = model.predict(x_test)
    mae_bps = mean_absolute_error(y_test, preds) * 10_000
    print(f"Test MAE: {mae_bps:.2f} bps across {len(TENOR_COLS)} tenors")

    os.makedirs(args.out_dir, exist_ok=True)
    n_features = x.shape[1]
    onnx_model = to_onnx(
        model,
        initial_types=[("input", FloatTensorType([None, n_features]))],
        target_opset=17,
    )
    onnx_path = os.path.join(args.out_dir, "rate_forecast.onnx")
    with open(onnx_path, "wb") as f:
        f.write(onnx_model.SerializeToString())

    meta = {
        "name": "rate-forecast",
        "task": "tabular-regression",
        "lookback": args.lookback,
        "tenors": TENOR_COLS,
        "n_features": n_features,
        "input_name": "input",
        "test_mae_bps": round(float(mae_bps), 2),
    }
    with open(os.path.join(args.out_dir, "model_metadata.json"), "w") as f:
        json.dump(meta, f, indent=2)

    size_kb = os.path.getsize(onnx_path) / 1024
    print(f"Exported ONNX -> {onnx_path} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()

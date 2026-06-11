"""
Validate the exported ONNX rate-forecast model with ONNX Runtime.

Loads the model, runs a forward pass on the last window from the dataset, and
prints the predicted next-day curve. Acts as a fast local gate before we
package and push the model to ACR for edge deployment.
"""
from __future__ import annotations

import argparse
import json
import os

import numpy as np
import pandas as pd

TENOR_LABELS = ["1M", "3M", "6M", "1Y", "2Y", "3Y", "5Y", "7Y", "10Y"]
TENOR_COLS = [f"y_{m}m" for m in (1, 3, 6, 12, 24, 36, 60, 84, 120)]


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate ONNX rate forecaster.")
    parser.add_argument(
        "--model",
        default=os.path.join(os.path.dirname(__file__), "artifacts", "rate_forecast.onnx"),
    )
    parser.add_argument(
        "--meta",
        default=os.path.join(os.path.dirname(__file__), "artifacts", "model_metadata.json"),
    )
    parser.add_argument(
        "--data",
        default=os.path.join(os.path.dirname(__file__), "data", "rates.csv"),
    )
    args = parser.parse_args()

    import onnxruntime as ort

    with open(args.meta) as f:
        meta = json.load(f)
    lookback = meta["lookback"]

    df = pd.read_csv(args.data)
    window = df[TENOR_COLS].to_numpy(dtype=np.float32)[-lookback:]
    x = window.flatten().reshape(1, -1).astype(np.float32)

    sess = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])
    input_name = sess.get_inputs()[0].name
    pred = sess.run(None, {input_name: x})[0].ravel()

    print("Predicted next-day yield curve:")
    for label, value in zip(TENOR_LABELS, pred):
        print(f"  {label:>4}: {value * 100:6.3f}%")

    assert pred.shape[0] == len(TENOR_COLS), "Unexpected output shape"
    assert np.all(pred >= 0), "Negative yields detected"
    print("\nValidation OK")


if __name__ == "__main__":
    main()

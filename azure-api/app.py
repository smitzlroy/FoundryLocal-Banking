"""Act 1 cloud inference service for the Sovereign Rate-Forecast demo.

A small FastAPI + ONNX Runtime service that serves the predictive yield-curve
model. It deliberately REPLICATES the Foundry Local on Azure Local *predictive*
inference contract (the base64 `items` envelope on /v1/predict, the X-API-KEY
header, and the metadata+items response) so the dashboard can point at this
cloud service (Act 1) or at the Azure Local edge deployment (Act 2) with no code
change.

Contract (matches the Foundry Local predictive server):
    GET  /healthz | /health   -> liveness (public)
    GET  /readyz  | /ready    -> readiness (public)
    GET  /v1/models           -> list (public)
    GET  /v1/model            -> model metadata (input_shape, outputs, ...)
    POST /v1/predict          -> predictive inference (requires X-API-KEY if configured)
        body: {"items":[{"content_type":"application/json","encoder":"base64",
                          "data":"<base64 of a JSON numeric array>"}]}
        resp: {"metadata":{"model_id","batch_size","inference_time_ms"},
               "items":[{"content_type":"application/json","encoder":"base64",
                         "data":"<base64 of JSON object>"}]}
        decoded resp data: {"<outputName>_<index>": [[...values...]]}

Inputs/outputs are decimal yields (0.0485 == 4.85%), matching the trained model.
"""
from __future__ import annotations

import base64
import json
import os
import time
from pathlib import Path
from typing import Any, List

import numpy as np
import onnxruntime as ort
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

MODEL_PATH = os.environ.get("MODEL_PATH", "/models/rate_forecast.onnx")
META_PATH = os.environ.get("META_PATH", "/models/model_metadata.json")
MODEL_ID = os.environ.get("MODEL_ID", "rate-forecast:v1")
# When set, /v1/predict requires a matching X-API-KEY header (mirrors edge auth).
API_KEY = os.environ.get("API_KEY", "")

app = FastAPI(title="Sovereign Rate-Forecast Inference (Act 1 cloud)", version="1.0.0")

_session: ort.InferenceSession | None = None
_input_name: str = "input"
_output_names: List[str] = []
_meta: dict = {}


def _load() -> None:
    """Load the ONNX session and metadata once at startup."""
    global _session, _input_name, _output_names, _meta
    if not Path(MODEL_PATH).exists():
        raise RuntimeError(f"Model not found at {MODEL_PATH}")
    _session = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
    _input_name = _session.get_inputs()[0].name
    _output_names = [o.name for o in _session.get_outputs()]
    if Path(META_PATH).exists():
        with open(META_PATH) as f:
            _meta = json.load(f)


@app.on_event("startup")
def startup() -> None:
    _load()


class PredictItem(BaseModel):
    content_type: str = "application/json"
    encoder: str = "base64"
    data: str = Field(..., description="base64-encoded JSON array of input tensor values")


class PredictRequest(BaseModel):
    items: List[PredictItem] = Field(..., description="Exactly one item per request")


def _require_key(x_api_key: str | None) -> None:
    if API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="invalid_api_key")


# ---- Public (no-auth) paths -------------------------------------------------
@app.get("/healthz")
@app.get("/health")
def healthz() -> dict:
    return {"status": "healthy" if _session is not None else "loading"}


@app.get("/readyz")
@app.get("/ready")
def readyz() -> dict:
    if _session is None:
        raise HTTPException(status_code=503, detail="model not loaded")
    return {"status": "ready"}


@app.get("/v1/models")
def models() -> dict:
    return {"object": "list", "data": [{"id": MODEL_ID}]}


@app.get("/v1/model")
def model_metadata() -> dict:
    if _session is None:
        raise HTTPException(status_code=503, detail="model not loaded")
    outs = [
        {"name": o.name, "shape": list(o.shape), "type": o.type}
        for o in _session.get_outputs()
    ]
    inp = _session.get_inputs()[0]
    return {
        "id": MODEL_ID,
        "name": _meta.get("name", MODEL_ID),
        "type": _meta.get("task", "tabular-regression"),
        "input_shape": list(inp.shape),
        "outputs": outs,
        "batch_size": 1,
        "execution_provider": "CPUExecutionProvider",
        "status": "loaded",
        "metadata": _meta,
    }


# ---- Predictive inference (auth-gated, Foundry Local contract) --------------
@app.post("/v1/predict")
def predict(req: PredictRequest, x_api_key: str | None = Header(default=None)) -> dict:
    _require_key(x_api_key)
    if _session is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")
    if len(req.items) != 1:
        raise HTTPException(status_code=400, detail="exactly one item per request is supported")

    item = req.items[0]
    if item.content_type != "application/json":
        raise HTTPException(status_code=400, detail=f"unsupported content_type {item.content_type}")
    try:
        decoded = base64.b64decode(item.data)
        values: Any = json.loads(decoded)
    except Exception as exc:  # noqa: BLE001 - boundary decode of caller input
        raise HTTPException(status_code=400, detail=f"invalid base64 JSON data: {exc}") from exc

    x = np.asarray(values, dtype=np.float32)
    if x.ndim == 1:
        x = x.reshape(1, -1)
    expected = int(_meta.get("n_features", x.shape[-1]))
    if x.shape[-1] != expected:
        raise HTTPException(
            status_code=400,
            detail=f"input has {x.shape[-1]} features, expected {expected}",
        )

    started = time.perf_counter()
    preds = _session.run(None, {_input_name: x})
    inference_ms = round((time.perf_counter() - started) * 1000, 2)

    # Build the decoded response object keyed "<outputName>_<index>".
    out_obj: dict = {}
    for out_name, arr in zip(_output_names, preds):
        out_obj[f"{out_name}_0"] = np.asarray(arr, dtype=np.float32).tolist()

    encoded = base64.b64encode(json.dumps(out_obj).encode("utf-8")).decode("ascii")
    return {
        "metadata": {
            "model_id": MODEL_ID,
            "batch_size": int(x.shape[0]),
            "inference_time_ms": inference_ms,
        },
        "items": [
            {"content_type": "application/json", "encoder": "base64", "data": encoded}
        ],
    }

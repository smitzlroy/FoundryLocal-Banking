"""Local smoke test for the Act 1 predictive API (Foundry Local contract)."""
import base64
import json
import sys
import urllib.request

BASE = "http://127.0.0.1:8077"
KEY = "testkey123"


def get(path):
    with urllib.request.urlopen(BASE + path) as r:
        return r.status, json.loads(r.read())


def post(path, body, key=None):
    data = json.dumps(body).encode()
    req = urllib.request.Request(path, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    if key:
        req.add_header("X-API-KEY", key)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


# 1. health / ready / model
print("healthz:", get("/healthz"))
print("readyz:", get("/readyz"))
st, meta = get("/v1/model")
print("model meta:", st, meta["input_shape"], [o["name"] for o in meta["outputs"]])

# 2. build a 90-feature vector (10 days x 9 tenors, decimal yields)
base = [0.0485, 0.0478, 0.0465, 0.0442, 0.0415, 0.0402, 0.0395, 0.0401, 0.0412]
features = base * 10
assert len(features) == 90
encoded = base64.b64encode(json.dumps([features]).encode()).decode()
envelope = {"items": [{"content_type": "application/json", "encoder": "base64", "data": encoded}]}

# 3. predict WITHOUT key -> expect 401
st, body = post(BASE + "/v1/predict", envelope, key=None)
print("predict no-key:", st, body)
assert st == 401, "auth gate failed"

# 4. predict WITH key -> expect 200 + decode
st, body = post(BASE + "/v1/predict", envelope, key=KEY)
print("predict status:", st)
assert st == 200, body
print("metadata:", body["metadata"])
item = body["items"][0]
out = json.loads(base64.b64decode(item["data"]))
key0 = list(out.keys())[0]
vals = out[key0][0] if isinstance(out[key0][0], list) else out[key0]
print("output key:", key0)
print("predicted (percent):", [round(v * 100, 3) for v in vals])
assert len(vals) == 9, "expected 9 outputs"
assert all(v > 0 for v in vals), "negative yields"
print("\nALL CHECKS PASSED")

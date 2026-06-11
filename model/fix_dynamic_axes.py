"""Name the dynamic batch axis on the rate-forecast ONNX model.

The Foundry Local predictive nginx sidecar /readyz endpoint validates the
model's input/output shape metadata with pydantic and requires every shape
entry to be a string (named dim) or int. An unnamed dynamic dimension
(dim_value == 0 with no dim_param) serializes to None and fails validation,
leaving the nginx-sidecar container NotReady.

This script sets dim_param="batch" on the first (batch) dimension of every
graph input and output so the metadata reports a valid string instead of None.
"""
import sys
import onnx

SRC = sys.argv[1] if len(sys.argv) > 1 else "model/artifacts/rate_forecast.onnx"
DST = sys.argv[2] if len(sys.argv) > 2 else SRC


def name_batch_dim(value_infos):
    for vi in value_infos:
        dims = vi.type.tensor_type.shape.dim
        if not dims:
            continue
        first = dims[0]
        # Unnamed dynamic dim => dim_value 0 and empty dim_param.
        if not first.dim_param and first.dim_value in (0,):
            first.ClearField("dim_value")
            first.dim_param = "batch"


model = onnx.load(SRC)
name_batch_dim(model.graph.input)
name_batch_dim(model.graph.output)
onnx.checker.check_model(model)
onnx.save(model, DST)

# Report result
for group, items in (("INPUTS", model.graph.input), ("OUTPUTS", model.graph.output)):
    print(group)
    for it in items:
        shape = [(d.dim_param or d.dim_value) for d in it.type.tensor_type.shape.dim]
        print(" ", it.name, shape)
